"""Zips files at the ROOT of an archive, with no wrapper folder (SPEC 72).

    python tools/zipdir.py out.zip <dir> [names...]

With no names, everything under <dir> goes in; with names, only those (files or folders). Used by
deploy/release.sh where the `zip` command is missing -- Git Bash on Windows has no `zip`, and a release
built on the dev machine must contain exactly what a release built by CI contains. Entries are sorted and
timestamps fixed, so the same build twice gives the same bytes.
"""
import os
import sys
import zipfile

FIXED_TIME = (2026, 1, 1, 0, 0, 0)


def entries(root, names):
    picked = names or sorted(os.listdir(root))
    for name in picked:
        path = os.path.join(root, name)
        if os.path.isdir(path):
            for dirpath, dirnames, filenames in os.walk(path):
                dirnames.sort()
                for f in sorted(filenames):
                    full = os.path.join(dirpath, f)
                    yield full, os.path.relpath(full, root).replace(os.sep, "/")
        elif os.path.exists(path):
            yield path, name.replace(os.sep, "/")
        else:
            sys.exit("zipdir: %s does not exist" % path)


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out, root, names = sys.argv[1], sys.argv[2], sys.argv[3:]
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for full, arc in entries(root, names):
            info = zipfile.ZipInfo(arc, FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            # Keep the executable bit: a Linux build that arrives without +x is a support ticket.
            mode = 0o755 if (os.stat(full).st_mode & 0o111 or arc.endswith((".sh", ".x86_64", ".arm64"))) else 0o644
            info.external_attr = mode << 16
            with open(full, "rb") as f:
                z.writestr(info, f.read())
    print("  %s" % out)


if __name__ == "__main__":
    main()
