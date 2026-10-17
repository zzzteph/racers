#!/bin/sh
# THE ONE COMMAND THAT SAYS WHETHER THE GAME IS GOOD (SPEC 128).
#
#   sh tools/verify.sh                    # uses `godot` from PATH
#   GODOT=/c/.../godot.exe sh tools/verify.sh
#
# The suite's own "N passed, 0 failed" line was never the whole truth. GDScript ABORTS a function the
# moment it touches a method that no longer exists, and an aborted test function increments nothing --
# it simply stops, and the assertions after it never run. Eight test functions had been aborting that
# way since SPEC 116 deleted the fight, and the summary went on saying 0 failed.
#
# So this checks three things, and any one of them fails the run:
#   1. the suite's own failure count,
#   2. SCRIPT ERROR / "Invalid call" / "Invalid access" anywhere in its output -- an aborted function,
#   3. the layout sweep's problem count.
#
# Known-harmless engine noise is filtered by name rather than by ignoring errors wholesale: the
# certificate store (no CA bundle in a headless run) and SubViewport sizing warnings say nothing about
# the game. Everything else is a failure.
set -e
cd "$(dirname "$0")/.."

GODOT="${GODOT:-godot}"
OUT="${OUT:-build/verification}"
mkdir -p "$OUT"

fail=0

echo "--- suite"
"$GODOT" --headless --path . --script res://tests/run_tests.gd > "$OUT/suite-output.txt" 2>&1 || true
tail -n 3 "$OUT/suite-output.txt" | grep -a "Summary" || true

if ! grep -aq "0 failed ===" "$OUT/suite-output.txt"; then
  echo "FAILED: the suite reports failing assertions." >&2
  grep -a "^FAIL" "$OUT/suite-output.txt" | head -40 >&2
  fail=1
fi

# An aborted test function. `grep -v` removes only the two engine messages named above.
noise='certificate|CA bundle|SubViewport|RID allocations|ObjectDB instances|still in use at exit|was leaked'
if grep -aE "SCRIPT ERROR|Invalid call|Invalid access|Parse Error|Compile Error" "$OUT/suite-output.txt" \
     | grep -avE "$noise" | head -40 > "$OUT/suite-errors.txt"; then
  if [ -s "$OUT/suite-errors.txt" ]; then
    echo "FAILED: the suite printed script errors -- a test function aborted and its checks never ran." >&2
    cat "$OUT/suite-errors.txt" >&2
    fail=1
  fi
fi

# An RPC to a peer that is not there means a fixture is talking to a socket that does not exist.
if grep -aq "Attempt to call RPC with unknown peer" "$OUT/suite-output.txt"; then
  echo "FAILED: the suite sent RPCs to peers that are not connected." >&2
  fail=1
fi

echo "--- layout sweep"
"$GODOT" --headless --path . --script res://tools/check_overlaps.gd > "$OUT/layout-output.txt" 2>&1 || true
tail -n 2 "$OUT/layout-output.txt" | grep -a "problem" || true
if ! grep -aq "^0 problems" "$OUT/layout-output.txt"; then
  echo "FAILED: the layout sweep found problems." >&2
  grep -aE "^    " "$OUT/layout-output.txt" | head -20 >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "VERIFICATION FAILED.  Logs in $OUT/"
  exit 1
fi
echo ""
echo "Verified: assertions pass, no script errors, no layout problems.  Logs in $OUT/"
