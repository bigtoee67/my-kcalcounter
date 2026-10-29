# Cronometer MCP server for Claude (web + mobile), hosted on Render's free tier.
#
# Based on the upstream image in rwestergren/cronometer-api-mcp, with two changes:
#   1. Installs the published PyPI release (pinned) instead of copying source.
#   2. Serves MCP at a secret path, /<MCP_SECRET>/mcp, because the server has
#      no login of its own. Any other path returns 404.
#
# Nothing personal lives in this file, so the GitHub repo holding it can be
# public. Everything private goes in Render -> your service -> Environment:
#   MCP_SECRET              long random string; becomes part of your private URL
#   CRONOMETER_USERNAME     your Cronometer email
#   CRONOMETER_PASSWORD     your Cronometer password
#   CRONOMETER_TOTP_SECRET  only if your Cronometer account uses 2FA
#   CRONOMETER_ACCOUNT_TZ   optional, e.g. Asia/Karachi

FROM supercorp/supergateway:uvx@sha256:2ffee900c18d8375096b392c8be15cd344535a05b753a5b182da227ab6306a15

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1 \
    UV_PYTHON_INSTALL_DIR=/opt/uv-python \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_TOOL_BIN_DIR=/usr/local/bin \
    PORT=10000 \
    HOME=/tmp \
    XDG_CACHE_HOME=/tmp/.cache

# Python 3.14 + the Cronometer MCP server from PyPI (pinned release).
RUN uv python install 3.14 \
    && uv tool install --python 3.14 cronometer-api-mcp==0.2.6 \
    && chmod -R a+rX /opt/uv-python /opt/uv-tools

# Same fix as upstream: newer MCP SDK inside supergateway so claude.ai's
# protocol version is accepted (otherwise Claude connects but sees no tools).
RUN cd /usr/local/lib/node_modules/supergateway \
    && npm install @modelcontextprotocol/sdk@^1.29.0 --no-save --no-audit --no-fund

# Logging is off (--logLevel none below) so the secret URL and your food data
# never appear in logs. Runs as a non-root user; /tmp holds the login cache.
USER 1000

ENTRYPOINT ["/bin/sh", "-c", "if [ -z \"$MCP_SECRET\" ]; then echo 'MCP_SECRET is not set' >&2; exit 1; fi; exec supergateway --stdio cronometer-api-mcp --outputTransport streamableHttp --stateful --streamableHttpPath \"/$MCP_SECRET/mcp\" --healthEndpoint /healthz --port \"$PORT\" --sessionTimeout 3600000 --logLevel none"]
