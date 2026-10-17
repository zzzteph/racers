# syntax=docker/dockerfile:1
# Rope Racers -- everything in ONE container, on ONE port (8080):
#   /ws            the game server (WebSocket)  -> the Godot dedicated server inside, on 127.0.0.1:7777
#   /api/servers   the server list (the server's own entry, rewritten every 10 s)
#   /              the web version of the game
#   /healthz       "ok"
#
#   Cloudflare (proxied, SSL Flexible) --http--> nginx on your VPS --http--> this container on 127.0.0.1:8080
#
# Build context = this folder, after `sh package.sh` copied in:  server/RopeRacersServer.x86_64  and  web/
#   docker build -t rope-racers .
#   docker run -d --name rope-racers --restart unless-stopped -p 127.0.0.1:8080:8080 \
#     -v rope-racers-data:/app/.local/share rope-racers
# (redeploy.sh does exactly this on your VPS.) Change a setting with -e, e.g. -e RR_NAME="My server".
# The volume is where Godot keeps `user://` (HOME is /app): the leaderboard (SPEC 111) lives there, and
# a container replaced without it starts the table from zero. The directory exists in the image, owned
# by the server's user, so a named volume mounted there is writable from the first start.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates libfontconfig1 nginx \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 10001 --home /app racer \
 && mkdir -p /app/.local/share /run/rope /tmp/nginx /etc/rope \
 && chown -R racer /app /run/rope /tmp/nginx

# --- the game ---
COPY --chown=racer --chmod=755 server/RopeRacersServer.x86_64 /app/RopeRacersServer.x86_64
COPY web/ /srv/web/

# --- the web front inside the container (not your VPS nginx) ---
COPY <<'EOF' /etc/rope/nginx.conf
worker_processes 1;
pid /tmp/nginx/nginx.pid;
error_log stderr warn;
events { worker_connections 1024; }
http {
    include /etc/nginx/mime.types;
    types { application/wasm wasm; }
    default_type application/octet-stream;
    access_log off;
    sendfile on;
    client_body_temp_path /tmp/nginx/client;
    proxy_temp_path       /tmp/nginx/proxy;
    fastcgi_temp_path     /tmp/nginx/fastcgi;
    uwsgi_temp_path       /tmp/nginx/uwsgi;
    scgi_temp_path        /tmp/nginx/scgi;
    map $http_upgrade $connection_upgrade { default upgrade; '' close; }
    server {
        listen 8080;
        location /ws {
            proxy_pass http://127.0.0.1:7777;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;
            proxy_set_header Host $host;
            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
            proxy_buffering off;
        }
        location = /api/servers {
            alias /run/rope/servers.json;
            default_type application/json;
            add_header Cache-Control "no-store" always;
            add_header Access-Control-Allow-Origin "*" always;
        }
        location = /healthz {
            default_type text/plain;
            return 200 "ok\n";
        }
        location / {
            root /srv/web;
            index index.html;
            try_files $uri $uri/ =404;
            add_header Cross-Origin-Opener-Policy "same-origin" always;
            add_header Cross-Origin-Embedder-Policy "require-corp" always;
            add_header Cache-Control "no-cache" always;
        }
        gzip on;
        gzip_types application/javascript application/wasm application/json text/css;
    }
}
EOF

# --- runs both; if either dies the container stops and Docker restarts it ---
COPY --chmod=755 <<'EOF' /app/start.sh
#!/bin/bash
set -u
echo '{"servers":[]}' > "$RR_STATUS_FILE"
/app/RopeRacersServer.x86_64 --headless -- --server &
GAME=$!
nginx -e stderr -c /etc/rope/nginx.conf -g 'daemon off;' &
WEB=$!
trap 'kill -TERM $GAME $WEB 2>/dev/null; wait; exit 0' TERM INT
wait -n $GAME $WEB
CODE=$?
echo "[start.sh] a process exited ($CODE) -- stopping the container"
kill -TERM $GAME $WEB 2>/dev/null
wait
exit $CODE
EOF

USER racer
WORKDIR /app
# The server's settings. Override any of them with `docker run -e NAME=value`.
ENV HOME=/app \
    RR_PORT=7777 \
    RR_STATUS_FILE=/run/rope/servers.json \
    RR_NAME="The Naked Cat - Official" \
    RR_MOTD="Welcome to Rope Racers! Quick Join or make your own room." \
    RR_PUBLIC_URL="wss://rope.thenakedcat.games/ws" \
    RR_MAX_ROOMS=32 \
    RR_MAX_PLAYERS=96
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s \
  CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/8080 && printf "GET /healthz HTTP/1.0\r\n\r\n" >&3 && grep -q ok <&3'
CMD ["/app/start.sh"]
