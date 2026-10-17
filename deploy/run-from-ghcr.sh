#!/bin/sh
# One command on the server, once the image is in GitHub's registry (SPEC 66):
#
#   sh run-from-ghcr.sh                    # ghcr.io/zzzteph/rope-racers:latest (TAG=0.11.3 pins a version)
#   sh run-from-ghcr.sh youruser            # a fork under another owner (or OWNER=youruser)
#
# It pulls the published image, replaces the running container and checks it answers. No repository, no
# Godot, no build on the server -- the image already contains the game server, the web build and nginx.
set -e
OWNER="${1:-${OWNER:-zzzteph}}"        # the repository lives under zzzteph; pass another owner to use a fork
IMAGE="ghcr.io/$OWNER/rope-racers:${TAG:-latest}"

echo "== pulling $IMAGE"
docker pull "$IMAGE"
docker rm -f rope-racers >/dev/null 2>&1 || true
# The named volume keeps the leaderboard (and anything else the server writes) across deploys.
docker run -d --name rope-racers --restart unless-stopped -p 127.0.0.1:8080:8080 \
  -v rope-racers-data:/app/.local/share "$IMAGE"
docker image prune -f >/dev/null
sleep 3
curl -fsS http://127.0.0.1:8080/healthz && echo
curl -fsS http://127.0.0.1:8080/api/servers && echo
echo "== running. Point your nginx at 127.0.0.1:8080 (deploy/nginx/rope.thenakedcat.games.conf)."
