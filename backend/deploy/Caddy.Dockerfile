FROM caddy:2-alpine
RUN addgroup -g 10001 leanguard && adduser -D -H -u 10001 -G leanguard leanguard \
    && mkdir -p /data/caddy /config/caddy && chown -R 10001:10001 /data /config
USER 10001:10001
