FROM node:20-alpine

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# Install dependencies using cache layers
COPY --chown=node:node package*.json ./
RUN npm ci --omit=dev

# Copy application source code
COPY --chown=node:node . .

# Run as non-root user
USER node

EXPOSE 3000

CMD ["node", "server.js"]
