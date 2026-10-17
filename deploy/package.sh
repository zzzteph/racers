#!/bin/sh
# Puts the latest exports where the deploy files expect them:
#   build/server/RopeRacersServer.x86_64  -> deploy/server/   (the Docker image's contents)
#   build/web/*                           -> deploy/web/      (served inside the container)
# Run from the project folder after exporting the "Linux Server" and "Web" presets (redeploy.sh does all of
# it, upload included).
set -e
cd "$(dirname "$0")/.."
# This runs on the machine you EXPORT from (the one with Godot), never on the server: all it does is
# copy build/ into deploy/. On the server you need only Dockerfile + server/ + web/, and `docker build`.
if [ ! -f build/server/RopeRacersServer.x86_64 ] || [ ! -f build/web/index.html ]; then
  echo "No exports in build/ -- nothing to package."
  echo
  echo "This script runs on the machine with Godot, not on the server."
  echo "  On your PC:      sh deploy/redeploy.sh user@your-vps   (exports, uploads, rebuilds, restarts)"
  echo "  On the server:   cd to the folder holding Dockerfile, server/ and web/, then"
  echo "                   docker build -t rope-racers . && docker rm -f rope-racers;"
  echo "                   docker run -d --name rope-racers --restart unless-stopped \\"
  echo "                     -p 127.0.0.1:8080:8080 rope-racers"
  exit 1
fi
mkdir -p deploy/server
cp build/server/RopeRacersServer.x86_64 deploy/server/
rm -rf deploy/web && mkdir -p deploy/web
cp build/web/*.html build/web/*.js build/web/*.wasm build/web/*.pck build/web/*.png deploy/web/ 2>/dev/null || true
echo "deploy/ is ready: server binary + web build copied."
