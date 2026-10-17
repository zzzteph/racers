# Deploying Rope Racers — rope.thenakedcat.games

```
 players ──https──▶ Cloudflare (proxied, Flexible) ──http──▶ nginx on your VPS ──http──▶ Docker: rope-racers (127.0.0.1:8080)
                                                                              ├─ /ws           the game server
                                                                              ├─ /api/servers  the server list
                                                                              └─ /             the web game
```

Everything lives in **one container** built from **one Dockerfile**. Cloudflare does HTTPS; your nginx only
passes everything on. The desktop games connect to `wss://rope.thenakedcat.games/ws` (Multiplayer → ONLINE).

## Once

**1. Cloudflare** (dashboard for thenakedcat.games)

* **DNS** -> Add record: `A`, name `rope`, your VPS's IP, **Proxied** (orange cloud).
* **SSL/TLS -> Overview** -> **Flexible** (Cloudflare does HTTPS; it talks to your VPS over plain HTTP).
* **SSL/TLS -> Edge Certificates** -> **Always Use HTTPS**: On.
* **Network** -> WebSockets: On (the default).

No certificate on the VPS. Open port **80** to Cloudflare.

**2. nginx** on the VPS -- `nginx/rope.thenakedcat.games.conf` (plain HTTP, port 80):

```sh
sudo cp rope.thenakedcat.games.conf /etc/nginx/sites-available/
sudo ln -s /etc/nginx/sites-available/rope.thenakedcat.games.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

Do not add an http -> https redirect in nginx: with Flexible it loops forever (Cloudflare redirects instead).
If `nginx -t` says `$connection_upgrade` is defined twice, delete the `map { ... }` block at the top of the
file -- your nginx.conf already has it.

**3. Docker** on the VPS (`curl -fsSL https://get.docker.com | sh`), and SSH access from your PC.

## Every time (from your PC)

```sh
sh deploy/redeploy.sh you@your-vps
```

It exports the server and the web game, uploads them with the Dockerfile to `~/rope-racers`, builds the
image and replaces the container, then prints `ok` and the server list. Players in a race are dropped for
a few seconds and reconnect to their room by themselves.

Check: `https://rope.thenakedcat.games` (the web game), `https://rope.thenakedcat.games/api/servers`
(your server, its players and rooms).

## By hand, on the VPS

```sh
cd ~/rope-racers
docker build -t rope-racers .
docker rm -f rope-racers
docker run -d --name rope-racers --restart unless-stopped -p 127.0.0.1:8080:8080 -v rope-racers-data:/app/.local/share rope-racers
docker logs -f rope-racers
```

## Settings

Defaults are in the Dockerfile; change any with `-e` on `docker run`:

| Variable | Default | What |
| --- | --- | --- |
| `RR_NAME` | The Naked Cat - Official | the server's name (server list, title bar) |
| `RR_MOTD` | Welcome to Rope Racers! ... | one line over the room list |
| `RR_PUBLIC_URL` | wss://rope.thenakedcat.games/ws | the address in the server list |
| `RR_MAX_ROOMS` | 32 | rooms at once |
| `RR_MAX_PLAYERS` | 96 | players at once |

## Optional: a directory of several servers

With more than one server, `extras/cloudflare/` is a Cloudflare Worker that keeps one list for all of them
(each server checks in with `RR_REGISTER_URL` / `RR_REGISTER_KEY`). Not needed for one server.

## From GitHub's registry (SPEC 66)

Pushing to `main` (or a `v*` tag) builds the image in GitHub Actions (`.github/workflows/server-image.yml`):
it runs the test suite, exports the Linux Server and Web builds, and publishes

    ghcr.io/zzzteph/rope-racers:latest          the newest push to main
    ghcr.io/zzzteph/rope-racers:<version>       e.g. 0.11.3, from project.godot
    ghcr.io/zzzteph/rope-racers:<commit sha>    exactly one commit

On the server, that makes a deploy one command -- no repository, no Godot, no build:

    sh run-from-ghcr.sh zzzteph              # pulls :latest, restarts the container, checks /healthz
    TAG=0.11.3 sh run-from-ghcr.sh zzzteph   # a pinned version (also how you roll back)

or by hand:

    docker pull ghcr.io/zzzteph/rope-racers:latest
    docker rm -f rope-racers 2>/dev/null || true
    docker run -d --name rope-racers --restart unless-stopped \
      -p 127.0.0.1:8080:8080 -v rope-racers-data:/app/.local/share ghcr.io/zzzteph/rope-racers:latest

The `rope-racers-data` volume keeps what the server writes -- the leaderboard (SPEC 111) above all --
across deploys; without it every new container starts the table from zero. `/app/.local/share` is inside
the container (Godot's `user://` is `.local/share/godot/app_userdata/Rope Racers/` under the server's
home, `/app`); the volume lives on the host under `/var/lib/docker/volumes/rope-racers-data/_data`, or
bind-mount a folder of your own owned by uid 10001 (`-v /srv/rope-racers/data:/app/.local/share`). The host nginx configuration
does not change: it still proxies :80 to 127.0.0.1:8080. The main README's "Deploying the server from
the GitHub image" walks through the first time.

**Make the package public** the first time (GitHub → your profile → Packages → rope-racers → Package
settings → Change visibility), or log the server in with `docker login ghcr.io` and a read:packages
token. The workflow itself needs no secret: `GITHUB_TOKEN` can push to its own repository's package.

