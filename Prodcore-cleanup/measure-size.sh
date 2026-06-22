#!/bin/bash
# Code-size metrics for the Prodcore working tree at its current checkout/state.
# Counts only Prodcore app Swift source — excludes build artifacts, checkouts.
# Symbol count is a lexical approximation (decl keywords at line start), consistent across refs.
# Usage: measure-size.sh [root]   (default root: ~/code/Prodcore/Prodcore)
# ponytail: lexical symbol grep, not a real parser — fine for before/after deltas on the same corpus.
set -euo pipefail
ROOT="${1:-$HOME/code/Prodcore}"

# Filelist to a temp file (works on bash 3.2 / macOS — no mapfile).
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
find "$ROOT" -name '*.swift' \
	-not -path '*/.build/*' \
	-not -path '*/SourcePackages/*' \
	-not -path '*/DerivedData/*' \
	-not -path '*/.git/*' > "$TMP"

files=$(wc -l < "$TMP" | tr -d ' ')
if [ "$files" -eq 0 ]; then printf 'files\t0\nloc\t0\nloc_nonblank\t0\nsymbols\t0\nbytes\t0\n'; exit 0; fi

CAT() { tr '\n' '\0' < "$TMP" | xargs -0 cat; }
loc=$(CAT | wc -l | tr -d ' ')
loc_nonblank=$(CAT | grep -cve '^[[:space:]]*$' || true)
bytes=$(CAT | wc -c | tr -d ' ')
symbols=$(CAT | grep -cE '^[[:space:]]*(public |private |fileprivate |internal |open |final |static |class |@[A-Za-z]+ )*(func|var|let|struct|class|enum|protocol|extension|actor|typealias|init|case) ' || true)

printf 'files\t%s\nloc\t%s\nloc_nonblank\t%s\nsymbols\t%s\nbytes\t%s\n' "$files" "$loc" "$loc_nonblank" "$symbols" "$bytes"
