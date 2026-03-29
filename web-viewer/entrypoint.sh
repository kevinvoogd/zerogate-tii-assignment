#!/bin/bash
# ---------------------------------------------------------------------------
# Entrypoint for the web-viewer container.
#
# Replaces placeholder signaling server config in the built web app with
# the actual host IP and ports provided via environment variables, then
# serves the production build on the configured WEB_PORT (default 8211).
# ---------------------------------------------------------------------------
set -e

SIGNALING_SERVER="${SIGNALING_SERVER:-127.0.0.1}"
SIGNALING_PORT="${SIGNALING_PORT:-49100}"
WEB_PORT="${WEB_PORT:-8211}"

# The built web app has a default config pointing to 127.0.0.1:49100.
# If a different server/port is specified, patch the built JS bundle.
if [ "$SIGNALING_SERVER" != "127.0.0.1" ] || [ "$SIGNALING_PORT" != "49100" ]; then
    echo "[web-viewer] Patching signaling config: ${SIGNALING_SERVER}:${SIGNALING_PORT}"
    find /app/web-viewer/dist -name '*.js' -exec \
        sed -i "s|signalingServer:\"127.0.0.1\"|signalingServer:\"${SIGNALING_SERVER}\"|g" {} +
    find /app/web-viewer/dist -name '*.js' -exec \
        sed -i "s|signalingPort:49100|signalingPort:${SIGNALING_PORT}|g" {} +
fi

echo "[web-viewer] Serving at http://0.0.0.0:${WEB_PORT}"
exec npx vite preview --host 0.0.0.0 --port "${WEB_PORT}"
