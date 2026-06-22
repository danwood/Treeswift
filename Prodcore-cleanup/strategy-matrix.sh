#!/bin/bash
# Exercise the 3 code-removal strategies across top-level Prodcore subfolders, across baselines.
#
# 3 nested loops: baseline × top-level-folder × strategy.
#   strategy 1 skipReferenced  — skip code still referenced by other unused code → expect BUILD OK
#   strategy 2 forceRemoveAll  — remove all unused → build MAY FAIL (may remove cross-referenced code)
#   strategy 3 cascade         — cascade removals → expect BUILD OK
# Scan is the expensive step, so it runs ONCE per baseline; the source is git-reset to the pristine
# baseline before EVERY strategy run (consistent baseline), and the cached scan still applies because
# the reset restores exactly the scanned source.
#
# For each (folder,strategy): execute folder-scoped removal, assert changes are ONLY inside that
# folder, build Prodcore, record build result + expected outcome. Reverts after each.
#
# Usage: strategy-matrix.sh "<ID> <commit> <signoff>" ["<ID> <commit> <signoff>" ...]
#        (default: all 5 baselines). Folders auto-discovered from the scan tree per baseline.
# Output: strategy-matrix-results.tsv (appended) + per-row log lines on stdout.
set -uo pipefail

PRODCORE="$HOME/code/Prodcore"
CFG="9E23EE49-A7B1-47BA-A5D6-DD150F7F15C7"
PORT="${PORT:-21663}"
BASE="http://localhost:$PORT"
H="$HOME/code/SWIFTUI/Treeswift/Prodcore-cleanup"
DD=$(cat /tmp/ts_dd.txt)
OUT="$H/strategy-matrix-results.tsv"
MAX_FOLDERS="${MAX_FOLDERS:-6}"   # cap folders per baseline (keeps runtime bounded); 0 = all

DEFAULT_BASELINES=("R3 23ad2547 1" "RMay 96e372e4 1" "R4 20fb9b87 1" "R5 a1711d27 1" "devbase 47a6d25de 0")
if [ "$#" -gt 0 ]; then BASELINES=("$@"); else BASELINES=("${DEFAULT_BASELINES[@]}"); fi

say() { echo ">>> $*"; }

build_prodcore() {
	# $1 = signoff flag. Returns 0 if BUILD SUCCEEDED, 1 otherwise; echoes distinct error count.
	local sign=()
	[ "$1" = "1" ] && sign=(CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO)
	local errs
	errs=$(xcodebuild -project "$PRODCORE/Prodcore.xcodeproj" -scheme Prodcore -configuration Debug \
		-destination 'platform=macOS' "${sign[@]}" build 2>&1 | grep -cE ' error: ')
	echo "$errs"
	[ "$errs" -eq 0 ]
}

restore_pristine() { (cd "$PRODCORE" && git restore . 2>/dev/null; git checkout . 2>/dev/null); }

printf 'baseline\tcommit\tfolder\tstrategy\tdeleted\tchangedFilesInFolder\tchangedFilesOutsideFolder\tbuildErrors\tbuildOK\texpected\tverdict\n' >> "$OUT"

for spec in "${BASELINES[@]}"; do
	set -- $spec
	ID="$1"; COMMIT="$2"; SIGNOFF="$3"
	BR="ts-matrix-$ID-$COMMIT"
	say "===== BASELINE $ID ($COMMIT) ====="
	(cd "$PRODCORE" && git switch -C "$BR" "$COMMIT" >/dev/null 2>&1) || { say "FATAL checkout $COMMIT"; continue; }
	restore_pristine

	# Launch fresh app against this checkout + scan ONCE.
	pkill -x Treeswift 2>/dev/null; sleep 2
	rm -f "$HOME/Library/Application Support/Treeswift/ScanCache/scan-cache-$CFG.json"
	rm -f /tmp/treeswift-control.json /tmp/treeswift-control.port
	open "$DD/Treeswift.app" --args --automation-port "$PORT"
	for i in $(seq 1 60); do curl -s --max-time 2 "$BASE/status" | grep -q '"state"' && break; sleep 1; done
	say "[$ID] scanning…"
	curl -s -X POST "$BASE/configurations/$CFG/scan" >/dev/null
	curl -s --max-time 2400 "$BASE/configurations/$CFG/scan/wait" >/dev/null
	curl -s "$BASE/configurations/$CFG/results/periphery-tree" > /tmp/matrix-tree-$ID.json

	# Discover top-level folder node IDs that actually contain unused-bearing files (the tree only
	# includes files/folders with warnings). Take folders with the most descendant file nodes first.
	# The tree root is a single 'Prodcore' folder node; the real top-level folders are its children.
	FOLDERS=$(python3 - "$ID" <<'PY'
import json, sys
ID = sys.argv[1]
d = json.load(open(f"/tmp/matrix-tree-{ID}.json"))
roots = d if isinstance(d, list) else [d]
def count_files(n):
    if not isinstance(n, dict): return 0
    if n.get("type") == "file": return 1
    return sum(count_files(c) for c in (n.get("children") or []))
# Descend into the single Prodcore root to reach the real top-level subfolders.
toplevel = []
for root in roots:
    if isinstance(root, dict):
        toplevel.extend(root.get("children") or [])
folders = []
for n in toplevel:
    if isinstance(n, dict) and n.get("type") == "folder":
        folders.append((count_files(n), n.get("id"), n.get("name")))
folders.sort(reverse=True)
for cnt, fid, name in folders:
    if cnt > 0:
        print(f"{fid}\t{name}\t{cnt}")
PY
)
	say "[$ID] candidate folders:"; echo "$FOLDERS" | sed 's/^/    /'

	n=0
	while IFS=$'\t' read -r FID FNAME FCNT; do
		[ -z "$FID" ] && continue
		n=$((n+1))
		if [ "$MAX_FOLDERS" -ne 0 ] && [ "$n" -gt "$MAX_FOLDERS" ]; then break; fi

		for STRAT in skipReferenced forceRemoveAll cascade; do
			restore_pristine
			EXPECT=$([ "$STRAT" = "forceRemoveAll" ] && echo "maybe" || echo "ok")

			RESP=$(curl -s -X POST "$BASE/configurations/$CFG/removal/execute" \
				-H "Content-Type: application/json" \
				-d "{\"strategy\":\"$STRAT\",\"nodeIds\":[\"$FID\"]}")
			DEL=$(echo "$RESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('totalDeleted',0))" 2>/dev/null || echo 0)

			# Changed files inside vs outside the folder (folder name matches a path segment).
			INSIDE=$(cd "$PRODCORE" && git -c core.quotepath=false diff --name-only | grep -c "/$FNAME/\|^$FNAME/" || true)
			OUTSIDE=$(cd "$PRODCORE" && git -c core.quotepath=false diff --name-only | grep -vc "/$FNAME/\|^$FNAME/" || true)

			ERRS=$(build_prodcore "$SIGNOFF"); BUILD_RC=$?
			BUILDOK=$([ "$BUILD_RC" -eq 0 ] && echo "OK" || echo "FAIL")

			# Verdict: opt1/opt3 must build OK; opt2 may be either.
			if [ "$STRAT" = "forceRemoveAll" ]; then VERD="info"
			elif [ "$BUILDOK" = "OK" ]; then VERD="PASS"; else VERD="UNEXPECTED-FAIL"; fi
			# Scope check: any change outside the folder is unexpected for a folder-scoped removal.
			if [ "${OUTSIDE:-0}" -gt 0 ]; then VERD="$VERD;LEAK-$OUTSIDE-outside"; fi

			printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
				"$ID" "$COMMIT" "$FNAME" "$STRAT" "$DEL" "${INSIDE:-0}" "${OUTSIDE:-0}" "$ERRS" "$BUILDOK" "$EXPECT" "$VERD" >> "$OUT"
			say "[$ID/$FNAME/$STRAT] deleted=$DEL inFolder=${INSIDE:-0} outside=${OUTSIDE:-0} build=$BUILDOK ($ERRS err) expect=$EXPECT verdict=$VERD"
			restore_pristine
		done
	done <<< "$FOLDERS"

	(cd "$PRODCORE" && git checkout . 2>/dev/null)
done

say "DONE strategy matrix → $OUT"
