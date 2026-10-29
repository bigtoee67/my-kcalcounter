# syntax=docker/dockerfile:1
# Cronometer MCP server for Claude (web + mobile), hosted on Render's free tier.
#
# Runs the server as ONE always-on web process (fast on Render's small free CPU),
# answering only at a secret path, /<MCP_SECRET>/mcp. Any other path returns 404.
#
# Nothing personal lives in this file. Private values go in Render -> Environment:
#   MCP_SECRET, CRONOMETER_USERNAME (your email), CRONOMETER_PASSWORD,
#   CRONOMETER_TOTP_SECRET (only with 2-step login)

FROM python:3.14-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PORT=10000 \
    HOME=/tmp \
    XDG_CACHE_HOME=/tmp/.cache

RUN pip install cronometer-api-mcp==0.2.6

COPY <<'EOF' /app/start.py
import os
import sys

# Secret path segment; .strip() ignores any stray space or line break pasted into Render.
secret = os.environ.get("MCP_SECRET", "").strip()
if not secret:
    print("MCP_SECRET is not set", file=sys.stderr)
    sys.exit(1)

# Render's value boxes can hold a stray space or line break that Cronometer's
# website ignores but its app login rejects; trim them so the login matches.
for _name in ("CRONOMETER_USERNAME", "CRONOMETER_PASSWORD", "CRONOMETER_TOTP_SECRET"):
    _raw = os.environ.get(_name)
    if _raw is not None and _raw != _raw.strip():
        os.environ[_name] = _raw.strip()
        print(f"Note: removed extra spaces or line breaks from {_name}", file=sys.stderr)

import uvicorn
from mcp.server.transport_security import TransportSecuritySettings
from starlette.responses import PlainTextResponse

from cronometer_api_mcp.server import mcp

import logging

logging.disable(logging.INFO)  # quiet routine logs (e.g. the login email); warnings still show


@mcp.custom_route("/healthz", methods=["GET"])
async def healthz(request):
    return PlainTextResponse("ok")


# One long-running process: the server starts once at boot instead of once per
# Claude connection. Stateless JSON mode survives Render restarts cleanly.
app = mcp.streamable_http_app(
    streamable_http_path=f"/{secret}/mcp",
    stateless_http=True,
    json_response=True,
    host="0.0.0.0",
    transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
)

uvicorn.run(
    app,
    host="0.0.0.0",
    port=int(os.environ.get("PORT", "10000")),
    log_level="warning",
    access_log=False,  # keeps the secret URL out of logs
    proxy_headers=True,
    forwarded_allow_ips="*",
)
EOF

USER 1000

CMD ["python", "/app/start.py"]
