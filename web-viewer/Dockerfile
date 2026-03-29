# =============================================================================
# Web Viewer — lightweight WebRTC client for Isaac Sim livestreaming.
#
# Connects to the Isaac Sim container's WebRTC signaling (port 49100) and
# media stream (port 47998) endpoints, then serves an interactive 3D viewport
# in the browser at http://<host>:8211
#
# Build args (injected by docker-compose):
#   SIGNALING_SERVER  — host IP or hostname for WebRTC signaling
#   SIGNALING_PORT    — TCP port for WebRTC signaling (default: 49100)
#   MEDIA_PORT        — UDP port for WebRTC media stream (default: 47998)
# =============================================================================

FROM node:22-slim

WORKDIR /app

# Install NVIDIA npm registry access for the Omniverse WebRTC client library
RUN echo 'registry=https://registry.npmjs.org/' > /root/.npmrc && \
    echo '@nvidia:registry=https://edge.urm.nvidia.com/artifactory/api/npm/omniverse-client-npm-local/' >> /root/.npmrc

# Install create-ov-web-sample globally
RUN npm install -g @nvidia/create-ov-web-sample@1.13.4 --ignore-scripts

# Generate a viewport-only web viewer app
RUN create-ov-web-sample --name="web-viewer" --sample=viewport-only --external --outputDir=/app

WORKDIR /app/web-viewer

# Install JS dependencies
RUN npm install --ignore-scripts

# Build the production bundle
RUN npx vite build

# Copy entrypoint that injects runtime config (host IP, ports)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8211

ENTRYPOINT ["/entrypoint.sh"]
