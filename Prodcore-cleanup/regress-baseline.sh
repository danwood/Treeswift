#!/bin/bash
# One baseline's live regression + size measurement.
# Drives the current (already-built, already-running) Treeswift via its automation API.
#
# Steps: restore pristine -> measure BEFORE -> pristine build (record error set) ->
#        cold scan -> forceRemoveAll preview+execute -> build Prodcore (NEW errors = FPs) ->
#        measure AFTER -> rescan (false-negative/convergence check) -> restore pristine.
#
# Assumes: Treeswift app already launched with --automation-port $PORT and config present.
# Usage: regress-baseline.sh <ID> <commit> <signoff:0|1>
# Writes a results block to stdout (TSV-ish) and a JSON line to results-<ID>.json.
set -uo pipefail

ID_LABEL="$1"; COMMIT="$2"; SIGNOFF="${3:-1}"
PRODCORE="$HOME/code/Prodcore"
CFG="9E23EE49-A7B1-47BA-A5D6-DD150F7F15C7"
PORT="${PORT:-21663}"
BASE="http://localhost:$PORT"
MEASURE="$HOME/code/SWIFTUI/Treeswift/Prodcore-cleanup/measure-size.sh"
OUT="$HOME/code/SWIFTUI/Treeswift/Prodcore-cleanup/results-$ID_LABEL.json"
BRANCH="ts-regress-$ID_LABEL-$COMMIT"

SIGN_FLAGS=()
if [ "$SIGNOFF" = "1" ]; then
	SIGN_FLAGS=(CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO)
fi

say() { echo ">>> [$ID_LABEL] $*"; }
errset() {
	# Build Prodcore; emit sorted unique error-message bodies (path/line stripped) to $1.
	# NOTE: no -disableAutomaticPackageResolution — pinning the baseline's stale Package.resolved
	# now FAILS resolution ("Could not resolve package dependencies"), which masks the true compile.
	# Letting xcodebuild resolve gives a real compile baseline; signing stays off for old baselines.
	xcodebuild -project "$PRODCORE/Prodcore.xcodeproj" -scheme Prodcore -configuration Debug \
		-destination 'platform=macOS' "${SIGN_FLAGS[@]}" build 2>&1 \
		| grep -E ' error: ' \
		| sed -E 's/^[^:]+:[0-9]+:[0-9]+: error: //' \
		| sort -u > "$1"
}

cd "$PRODCORE"

say "checkout pristine baseline $COMMIT on $BRANCH"
git switch -C "$BRANCH" "$COMMIT" >/dev/null 2>&1 || { say "FATAL: cannot switch to $COMMIT"; exit 2; }
git restore . 2>/dev/null; git checkout . 2>/dev/null   # revert tracked; never git clean -x (would drop gitignored Local.xcconfig)

say "measure BEFORE size"
"$MEASURE" "$PRODCORE" > /tmp/regress-before-$ID_LABEL.tsv
before_files=$(awk -F'\t' '/^files/{print $2}'  /tmp/regress-before-$ID_LABEL.tsv)
before_loc=$(awk -F'\t'   '/^loc\t/{print $2}'  /tmp/regress-before-$ID_LABEL.tsv)
before_locnb=$(awk -F'\t' '/^loc_nonblank/{print $2}' /tmp/regress-before-$ID_LABEL.tsv)
before_sym=$(awk -F'\t'   '/^symbols/{print $2}' /tmp/regress-before-$ID_LABEL.tsv)
before_bytes=$(awk -F'\t' '/^bytes/{print $2}'  /tmp/regress-before-$ID_LABEL.tsv)
say "BEFORE: files=$before_files loc=$before_loc nonblank=$before_locnb symbols=$before_sym bytes=$before_bytes"

say "pristine build (record baseline error set)"
errset /tmp/regress-pristine-$ID_LABEL.txt
pristine_errs=$(wc -l < /tmp/regress-pristine-$ID_LABEL.txt | tr -d ' ')
say "pristine build error lines: $pristine_errs (these are historical, subtracted)"

say "cold-clear ScanCache + relaunch Treeswift against this checkout"
DD=$(cat /tmp/ts_dd.txt)
pkill -x Treeswift 2>/dev/null; sleep 2
rm -f "$HOME/Library/Application Support/Treeswift/ScanCache/scan-cache-$CFG.json"
rm -f /tmp/treeswift-control.json /tmp/treeswift-control.port
open "$DD/Treeswift.app" --args --automation-port "$PORT"
# wait for the server to report ready
for i in $(seq 1 60); do
	if curl -s --max-time 2 "$BASE/status" | grep -q '"state"'; then say "server ready"; break; fi
	sleep 1
done

say "issuing scan"
curl -s -X POST "$BASE/configurations/$CFG/scan" >/dev/null
curl -s --max-time 1800 "$BASE/configurations/$CFG/scan/wait" >/dev/null
SUMMARY=$(curl -s "$BASE/configurations/$CFG/results/summary")
say "scan summary: $SUMMARY"

# Parse summary counts via python (robust).
read scan_total scan_unused scan_assign scan_redacc scan_redproto < <(python3 - "$SUMMARY" <<'PY'
import sys, json
d = json.loads(sys.argv[1] or "{}")
a = d.get("byAnnotation", {})
redacc = sum(v for k,v in a.items() if k.startswith("redundant") and "Accessib" in k)
print(d.get("totalCount",0), a.get("unused",0), a.get("assignOnlyProperty",0), redacc, a.get("redundantProtocol",0))
PY
)
say "parsed: total=$scan_total unused=$scan_unused assignOnly=$scan_assign redunAcc=$scan_redacc redunProto=$scan_redproto"

say "forceRemoveAll preview"
PREVIEW=$(curl -s -X POST "$BASE/configurations/$CFG/removal/preview" -H "Content-Type: application/json" -d '{"strategy":"forceRemoveAll"}')
read prev_del prev_nondel < <(python3 - "$PREVIEW" <<'PY'
import sys, json
d = json.loads(sys.argv[1] or "{}")
print(d.get("totalDeletable",0), d.get("totalNonDeletable",0))
PY
)
say "preview: deletable=$prev_del nonDeletable=$prev_nondel"

say "forceRemoveAll execute"
EXEC=$(curl -s -X POST "$BASE/configurations/$CFG/removal/execute" -H "Content-Type: application/json" -d '{"strategy":"forceRemoveAll"}')
read exec_deleted exec_err < <(python3 - "$EXEC" <<'PY'
import sys, json
d = json.loads(sys.argv[1] or "{}")
print(d.get("totalDeleted",0), len(d.get("errors",[])))
PY
)
say "execute: deleted=$exec_deleted execErrors=$exec_err"

say "build Prodcore after removal (NEW errors = false positives)"
errset /tmp/regress-post-$ID_LABEL.txt
post_errs=$(wc -l < /tmp/regress-post-$ID_LABEL.txt | tr -d ' ')
# NEW errors = post minus pristine.
new_errs=$(comm -13 /tmp/regress-pristine-$ID_LABEL.txt /tmp/regress-post-$ID_LABEL.txt | wc -l | tr -d ' ')
say "post build error lines: $post_errs ; NEW (false positives) = $new_errs"
comm -13 /tmp/regress-pristine-$ID_LABEL.txt /tmp/regress-post-$ID_LABEL.txt | head -30 > /tmp/regress-newerrs-$ID_LABEL.txt

say "measure AFTER size (post-removal tree)"
"$MEASURE" "$PRODCORE" > /tmp/regress-after-$ID_LABEL.tsv
after_files=$(awk -F'\t' '/^files/{print $2}'  /tmp/regress-after-$ID_LABEL.tsv)
after_loc=$(awk -F'\t'   '/^loc\t/{print $2}'  /tmp/regress-after-$ID_LABEL.tsv)
after_locnb=$(awk -F'\t' '/^loc_nonblank/{print $2}' /tmp/regress-after-$ID_LABEL.tsv)
after_sym=$(awk -F'\t'   '/^symbols/{print $2}' /tmp/regress-after-$ID_LABEL.tsv)
after_bytes=$(awk -F'\t' '/^bytes/{print $2}'  /tmp/regress-after-$ID_LABEL.tsv)
say "AFTER: files=$after_files loc=$after_loc nonblank=$after_locnb symbols=$after_sym bytes=$after_bytes"

say "emit JSON"
python3 - <<PY > "$OUT"
import json
print(json.dumps({
 "id":"$ID_LABEL","commit":"$COMMIT","signoff":$SIGNOFF,
 "before":{"files":$before_files,"loc":$before_loc,"loc_nonblank":$before_locnb,"symbols":$before_sym,"bytes":$before_bytes},
 "after":{"files":$after_files,"loc":$after_loc,"loc_nonblank":$after_locnb,"symbols":$after_sym,"bytes":$after_bytes},
 "scan":{"total":$scan_total,"unused":$scan_unused,"assignOnly":$scan_assign,"redunAcc":$scan_redacc,"redunProto":$scan_redproto},
 "removal":{"deletable":$prev_del,"nonDeletable":$prev_nondel,"deleted":$exec_deleted,"execErrors":$exec_err},
 "build":{"pristine_errs":$pristine_errs,"post_errs":$post_errs,"new_errs_false_positives":$new_errs}
}, indent=2))
PY
cat "$OUT"

say "restore Prodcore pristine"
git restore . 2>/dev/null
git checkout . 2>/dev/null
say "DONE $ID_LABEL"
