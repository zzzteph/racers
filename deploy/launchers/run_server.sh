#!/bin/sh
# Rope Racers dedicated server (Linux). Usage: ./run_server.sh [port]
# Players join with this machine's IP address; TCP port 7777 (or the one given) must be reachable.
cd "$(dirname "$0")"
chmod +x ./RopeRacers.x86_64 2>/dev/null
exec ./RopeRacers.x86_64 --headless -- --server --port "${1:-7777}"
