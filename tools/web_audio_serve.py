"""SPEC 139: serve build/web exactly as the container does, for the web-audio probe.

The point of this rather than `python -m http.server` is the HEADERS. The deployed nginx
(`deploy/Dockerfile`) sends Cross-Origin-Opener-Policy / Cross-Origin-Embedder-Policy and the wasm
MIME type, and any of those can change how the browser treats the page. A probe run against a plain
file server is not a probe of the thing players load.

    python tools/web_audio_serve.py [port] [directory]
"""
import functools
import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8099
ROOT = sys.argv[2] if len(sys.argv) > 2 else "build/web"


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = dict(http.server.SimpleHTTPRequestHandler.extensions_map)
    extensions_map.update({".wasm": "application/wasm", ".js": "text/javascript",
                           ".pck": "application/octet-stream"})

    def end_headers(self):
        # The same two the container sets.
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-cache")
        super().end_headers()

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    os.chdir(ROOT)
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
