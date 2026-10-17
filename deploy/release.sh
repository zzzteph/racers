#!/bin/sh
# Builds every download for one release (SPEC 72).
#
#   sh deploy/release.sh                          # uses `godot` from PATH
#   GODOT=/c/Users/me/godot.exe sh deploy/release.sh
#   PRESETS="linux server" sh deploy/release.sh   # only some of them
#   SKIP_TESTS=1 sh deploy/release.sh             # when the suite was just run by hand
#
# Exports all six presets, drops the right launcher next to each server-capable build, and zips them into
# build/release/ named after the version in project.godot:
#
#   RopeRacers-0.71.0-windows.zip      RopeRacers-0.71.0-linux.zip
#   RopeRacers-0.71.0-linux-arm64.zip  RopeRacers-0.71.0-macos.zip
#   RopeRacers-0.71.0-web.zip          RopeRacers-0.71.0-server.zip
#
# Nothing here is committed: build/ is ignored on purpose, and these zips are what a GitHub release
# carries. The same script runs in .github/workflows/release.yml, so a release made by hand and one made
# by a tag contain exactly the same files.
set -e
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
VERSION=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot)
# SPEC 113: the release notes ship inside the build as a script constant; bake them from CHANGELOG.md.
"$GODOT" --headless --path . --script res://tools/bake_release_notes.gd >/dev/null 2>&1 || {
  echo "Could not bake CHANGELOG.md into scripts/release_notes_data.gd (tools/bake_release_notes.gd)." >&2; exit 1; }
if [ -z "$VERSION" ]; then
  echo "No config/version in project.godot -- nothing to name the release after." >&2
  exit 1
fi
OUT="build/release"
echo "Rope Racers v$VERSION"

# The tests decide whether there is a release at all. A red suite is not a download.
if [ "${SKIP_TESTS:-0}" != "1" ]; then
  echo "--- tests"
  "$GODOT" --headless --path . --script res://tests/run_tests.gd | tee build/test.log | tail -3
  grep -q ", 0 failed" build/test.log || { echo "tests failed -- no release." >&2; exit 1; }
fi

echo "--- exports"
mkdir -p build/windows build/linux build/linux-arm64 build/macos build/web build/server "$OUT"
STARTED=$(date +%s)

# Godot exits 0 even when an export FAILS -- the commonest way being "cannot rename the temporary file",
# which is Windows saying the game is still running and holding its own .exe open. So every export is
# checked by hand afterwards: the file has to exist and be newer than this run.
export_preset() {  # export_preset <preset> <target>
  preset="$1"; target="$2"
  echo "  $preset -> $target"
  "$GODOT" --headless --path . --export-release "$preset" "$target" > build/export.log 2>&1 || true
  if [ ! -f "$target" ] || [ -n "$(find "$target" -newermt "@$STARTED" -prune -o -print 2>/dev/null)" ]; then
    echo >&2
    echo "EXPORT FAILED: $preset did not write $target." >&2
    grep -i "ERROR\|error:" build/export.log | head -5 >&2 || true
    case "$target" in
      *.exe) echo "Is the game still running? Close Rope Racers -- Windows will not let Godot replace a" >&2
             echo "running .exe, and Godot reports that as \"cannot rename the temporary file\"." >&2 ;;
    esac
    exit 1
  fi
}

# PRESETS names which to build (default: all). e.g. PRESETS="linux server" sh deploy/release.sh
for p in ${PRESETS:-windows linux linux-arm64 macos web server}; do
  case "$p" in
    # Its own folder, like every other platform: Windows will not let Godot overwrite an .exe that is
    # running, and build/RopeRacers.exe is exactly the one somebody is likely to be playing right now.
    windows)    export_preset "Windows Desktop" build/windows/RopeRacers.exe
                # Keep the familiar path fresh too. If the game is open the copy fails, and that is
                # reported at the END (see below): a warning in the middle of 400 lines of export log was
                # missed, and a stale build/RopeRacers.exe got played for two versions.
                cp build/windows/RopeRacers.exe build/RopeRacers.exe 2>/dev/null || STALE_EXE=1 ;;
    linux)      export_preset "Linux" build/linux/RopeRacers.x86_64 ;;
    linux-arm64) export_preset "Linux ARM64" build/linux-arm64/RopeRacers.arm64 ;;
    macos)      export_preset "macOS" build/macos/RopeRacers.zip ;;
    web)        export_preset "Web" build/web/index.html ;;
    server)     export_preset "Linux Server" build/server/RopeRacersServer.x86_64 ;;
    *) echo "Unknown preset \"$p\"." >&2; exit 1 ;;
  esac
done
rm -f build/RopeRacers.tmp build/export.log

# The launchers live in deploy/launchers/ (the only hand-written files that ship inside a build).
mkdir -p build/windows
cp deploy/launchers/RUN_SERVER.cmd build/windows/
cp deploy/launchers/RUN_SERVER.cmd build/ 2>/dev/null || true
cp deploy/launchers/run_server.sh build/linux/
cp deploy/launchers/run_server.sh build/linux-arm64/
cp deploy/launchers/run_server.sh build/server/
chmod +x build/linux/run_server.sh build/linux-arm64/run_server.sh build/server/run_server.sh 2>/dev/null || true
# Godot must not try to import its own exports when the editor next opens.
[ -f build/.gdignore ] || : > build/.gdignore

echo "--- zips"
rm -f "$OUT"/RopeRacers-*.zip
# Git Bash on Windows has no `zip`; tools/zipdir.py makes the same archive either way (contents at the
# root, no wrapper folder, +x kept on the Linux builds).
PY="${PYTHON:-python}"
command -v "$PY" >/dev/null 2>&1 || PY=python3
zip_dir() {  # zip_dir <name> <dir> [names...]
  name="$1"; dir="$2"; shift 2
  "$PY" tools/zipdir.py "$OUT/RopeRacers-$VERSION-$name.zip" "$dir" "$@"
}
for p in ${PRESETS:-windows linux linux-arm64 macos web server}; do
  case "$p" in
    windows)     zip_dir windows build/windows ;;
    linux)       zip_dir linux build/linux ;;
    linux-arm64) zip_dir linux-arm64 build/linux-arm64 ;;
    web)         zip_dir web build/web ;;
    server)      zip_dir server build/server ;;
    macos)  # already a .app bundle inside a zip; repacking it would lose the bundle's layout
            cp build/macos/RopeRacers.zip "$OUT/RopeRacers-$VERSION-macos.zip"
            echo "  $OUT/RopeRacers-$VERSION-macos.zip" ;;
  esac
done

# build/RopeRacers.exe is what gets double-clicked, so it is checked rather than trusted: the same size
# as the fresh export, or it is stale -- and stale is the LAST thing said, where it cannot be missed.
if [ -f build/windows/RopeRacers.exe ]; then
  fresh=$(wc -c < build/windows/RopeRacers.exe)
  have=$(wc -c < build/RopeRacers.exe 2>/dev/null || echo 0)
  if [ "${STALE_EXE:-0}" = "1" ] || [ "$fresh" != "$have" ]; then
    echo
    echo "############################################################################"
    echo "#  build/RopeRacers.exe is STALE: it could not be replaced (the game is    #"
    echo "#  probably open). The fresh build is build/windows/RopeRacers.exe and the #"
    echo "#  zips are current. Close the game and re-run to refresh the copy.        #"
    echo "############################################################################"
  fi
fi

echo
echo "v$VERSION is in $OUT/. To publish it:"
echo "  git tag v$VERSION && git push origin v$VERSION     (the release workflow builds and uploads)"
echo "  or: gh release create v$VERSION $OUT/RopeRacers-$VERSION-*.zip -F <notes>"
