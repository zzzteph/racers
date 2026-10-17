#!/bin/sh
# One command, from your PC (Git Bash on Windows is fine):
#   sh deploy/redeploy.sh you@your-vps
#
# 1. exports the server-only build and the web build (Godot, headless),
# 2. uploads Dockerfile + server + web to ~/rope-racers on the VPS,
# 3. rebuilds the image and replaces the running container there.
# Players in a race are dropped for a few seconds and reconnect to their room by themselves.
#
# GODOT=path/to/godot to use another Godot; SKIP_EXPORT=1 to upload what is already built.
set -e
HOST="${1:?usage: sh deploy/redeploy.sh user@your-vps}"
DIR="rope-racers"
cd "$(dirname "$0")/.."

if [ -z "${GODOT:-}" ]; then
  GODOT="/c/Users/steph/Downloads/godot/Godot_v4.7.2-stable_win64_console.exe"
  [ -x "$GODOT" ] || GODOT="godot"
fi
if [ "${SKIP_EXPORT:-0}" != "1" ]; then
  echo "== exporting"
  mkdir -p build/server build/web
  "$GODOT" --headless --path . --export-release "Linux Server" build/server/RopeRacersServer.x86_64
  "$GODOT" --headless --path . --export-release "Web" build/web/index.html
fi
sh deploy/package.sh

echo "== uploading to $HOST"
tar -C deploy -czf /tmp/rope-racers.tgz Dockerfile server web
scp /tmp/rope-racers.tgz "$HOST:/tmp/rope-racers.tgz"

echo "== rebuilding and restarting on $HOST"
ssh "$HOST" "set -e
  mkdir -p $DIR && rm -rf $DIR/web && tar -xzf /tmp/rope-racers.tgz -C $DIR && rm /tmp/rope-racers.tgz
  cd $DIR
  docker build -t rope-racers .
  docker rm -f rope-racers >/dev/null 2>&1 || true
  docker run -d --name rope-racers --restart unless-stopped -p 127.0.0.1:8080:8080 -v rope-racers-data:/app/.local/share rope-racers
  docker image prune -f >/dev/null
  sleep 3
  curl -fsS http://127.0.0.1:8080/healthz && curl -fsS http://127.0.0.1:8080/api/servers && echo"
echo "== done: https://rope.thenakedcat.games"
