# syntax=docker/dockerfile:1

# Pinned to a current Node.js LTS release for reproducible builds.
FROM node:24.22-alpine3.24

WORKDIR /app

ENV NODE_ENV=production \
    PORT=3000

# Install production dependencies first so this layer is cached.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund \
    && npm cache clean --force

# Copy application source with non-root ownership.
COPY --chown=node:node . .

# The admin panel writes .env.local at runtime, so /app must be writable.
RUN chown node:node /app

USER node

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD node -e "fetch('http://127.0.0.1:' + (process.env.PORT || 3000) + '/api/public-config').then((res) => process.exit(res.ok ? 0 : 1)).catch(() => process.exit(1))"

CMD ["node", "server.js"]
