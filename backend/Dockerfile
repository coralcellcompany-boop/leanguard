FROM node:22-bookworm-slim AS build
WORKDIR /build
COPY package*.json ./
RUN npm ci --ignore-scripts
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

FROM node:22-bookworm-slim AS runtime
ENV NODE_ENV=production
WORKDIR /app
RUN groupadd --gid 10001 leanguard && useradd --uid 10001 --gid 10001 --no-create-home leanguard \
    && mkdir -p /app/data/exports && chown -R leanguard:leanguard /app/data
COPY --chown=leanguard:leanguard package*.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY --from=build --chown=leanguard:leanguard /build/lib ./lib
COPY --chown=leanguard:leanguard migrations ./migrations
COPY --chown=leanguard:leanguard scripts ./scripts
USER 10001:10001
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/health/ready',{signal:AbortSignal.timeout(4000)}).then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "lib/index.js"]
