#!/usr/bin/env bash
# cleanup-unused-code.sh
#
# Rapidly eliminates real unused code from Prodcore by trying removals folder-by-folder.
# Uses skipReferenced strategy only. On build failure, git-restores and continues.
# Progress is saved to a JSON file so interrupted runs can resume.
#
# Usage:
#   bash scripts/cleanup-unused-code.sh [OPTIONS]
#
#   --skip-launch      Don't launch Treeswift; assume it's already running
#   --skip-scan        Skip Periphery scan; reuse cached results
#   --folder NAME      Only process this folder (repeatable)
#   --commit           Auto-commit after each successful folder (requires branch=dancleanup)
#   --dry-run          Preview what would be deleted without making changes
#   --reset-progress   Ignore existing progress file and start fresh
#
set -euo pipefail

# ──────────────────────────────────────────────────────────
# CONFIGURATION
# ──────────────────────────────────────────────────────────

PORT=21663
BASE_URL="http://127.0.0.1:$PORT"
PRODCORE_DIR="/Users/dwood/code/Prodcore"
PRODCORE_PROJECT="$PRODCORE_DIR/ProdCore.xcodeproj"
PRODCORE_SCHEME="Prodcore"
CONFIG_NAME="Prodcore-integration-test"
SCAN_TIMEOUT=600
BUILD_TIMEOUT=300
PROGRESS_FILE="/tmp/treeswift-cleanup-progress.json"
REQUIRED_BRANCH="dancleanup"

# ──────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ──────────────────────────────────────────────────────────

SKIP_LAUNCH=false
SKIP_SCAN=false
AUTO_COMMIT=false
DRY_RUN=false
RESET_PROGRESS=false
FOLDER_FILTER=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--skip-launch)    SKIP_LAUNCH=true;    shift ;;
		--skip-scan)      SKIP_SCAN=true;      shift ;;
		--commit)         AUTO_COMMIT=true;    shift ;;
		--dry-run)        DRY_RUN=true;        shift ;;
		--reset-progress) RESET_PROGRESS=true; shift ;;
		--folder)
			FOLDER_FILTER+=("$2")
			shift 2
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

# ──────────────────────────────────────────────────────────
# SOURCE HELPERS FROM INTEGRATION SCRIPT
# Strips the final `main "$@"` invocation to avoid running it.
# Imports: curl_post, curl_get, wait_for_server, launch_treeswift,
#   get_or_create_config, start_scan,
#   wait_for_scan, get_periphery_tree, collect_file_ids,
#   curl_post_resilient, preview_removal, execute_removal,
#   build_prodcore, git_reset_prodcore, wait_for_scan_with_heartbeat
# ──────────────────────────────────────────────────────────

SCRIPT_DIR="$(dirname "$0" | xargs realpath)"
_HELPERS_TMP=$(mktemp)
grep -v '^main ' "$SCRIPT_DIR/integration-test-removal.sh" > "$_HELPERS_TMP"

# Save our parsed flag values before sourcing — the integration script has
# global initializations (SKIP_SCAN=false, FOLDER_FILTER=(), etc.) that run
# during source and would clobber the values we parsed from our args.
_SAVED_SKIP_LAUNCH="$SKIP_LAUNCH"
_SAVED_SKIP_SCAN="$SKIP_SCAN"
_SAVED_AUTO_COMMIT="$AUTO_COMMIT"
_SAVED_DRY_RUN="$DRY_RUN"
_SAVED_RESET_PROGRESS="$RESET_PROGRESS"
_SAVED_FOLDER_FILTER=("${FOLDER_FILTER[@]+"${FOLDER_FILTER[@]}"}")

source "$_HELPERS_TMP"
rm -f "$_HELPERS_TMP"

# Restore our flag variables after sourcing.
SKIP_LAUNCH="$_SAVED_SKIP_LAUNCH"
SKIP_SCAN="$_SAVED_SKIP_SCAN"
AUTO_COMMIT="$_SAVED_AUTO_COMMIT"
DRY_RUN="$_SAVED_DRY_RUN"
RESET_PROGRESS="$_SAVED_RESET_PROGRESS"
FOLDER_FILTER=("${_SAVED_FOLDER_FILTER[@]+"${_SAVED_FOLDER_FILTER[@]}"}")

# Declare our own REPORT_FILE AFTER source so the sourced script's global
# assignments don't clobber ours (tlog() references $REPORT_FILE by name at
# call time, so this is safe as long as we set it before the first tlog() call).
REPORT_FILE="/tmp/treeswift-cleanup-$(date +%Y%m%d-%H%M%S).txt"

# ──────────────────────────────────────────────────────────
# PROGRESS PERSISTENCE HELPERS
# ──────────────────────────────────────────────────────────

progress_load() {
	if [[ -f "$PROGRESS_FILE" ]]; then
		tlog "Resuming from progress file: $PROGRESS_FILE"
		tlog "  (use --reset-progress to start fresh)"
	else
		# Create empty progress structure
		echo '{"processedFolders":{},"skippedFiles":{}}' > "$PROGRESS_FILE"
	fi
}

progress_folder_done() {
	local folder="$1"
	python3 - "$PROGRESS_FILE" "$folder" <<'EOF'
import sys, json
path, folder = sys.argv[1], sys.argv[2]
with open(path) as f: data = json.load(f)
print(data["processedFolders"].get(folder, ""))
EOF
}

progress_record_folder() {
	local folder="$1"
	local status="$2"  # cleaned, skipped, empty
	python3 - "$PROGRESS_FILE" "$folder" "$status" <<'EOF'
import sys, json
path, folder, status = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f: data = json.load(f)
data["processedFolders"][folder] = status
with open(path, "w") as f: json.dump(data, f, indent=2)
EOF
}

progress_record_skipped_files() {
	local folder="$1"
	shift
	local files=("$@")
	if [[ ${#files[@]} -eq 0 ]]; then return; fi
	python3 - "$PROGRESS_FILE" "$folder" "${files[@]}" <<'EOF'
import sys, json
path = sys.argv[1]
folder = sys.argv[2]
files = sys.argv[3:]
with open(path) as f: data = json.load(f)
for fp in files:
	data["skippedFiles"][fp] = f"build failed — folder: {folder}"
with open(path, "w") as f: json.dump(data, f, indent=2)
EOF
}

# ──────────────────────────────────────────────────────────
# CLEANUP-SPECIFIC HELPERS
# ──────────────────────────────────────────────────────────

# Like collect_file_ids but accepts a slash-separated path (e.g. "Features/Business").
# Walks the tree one component at a time, then collects all file IDs under the
# final node.
collect_file_ids_by_path() {
	local tree_json="$1"
	local folder_path="$2"
	# Split path on '/'
	IFS='/' read -ra _path_parts <<< "$folder_path"
	local current_json="$tree_json"
	for _part in "${_path_parts[@]}"; do
		current_json=$(echo "$current_json" | jq -r --arg n "$_part" \
			'map(select(.type=="folder" and .name==$n)) | first | .children // []')
		if [[ "$current_json" == "null" || "$current_json" == "[]" ]]; then
			echo "[]"
			return
		fi
	done
	echo "$current_json" | jq -r '.. | objects | select(.type=="file") | .id' \
		| jq -Rs 'split("\n") | map(select(length>0))'
}

# Extract filePaths from an execute_removal response where deletedCount > 0.
# Prints one path per line.
extract_modified_files() {
	local exec_response="$1"
	echo "$exec_response" | jq -r '.files[] | select(.deletedCount > 0) | .filePath'
}

# Extract all filePaths from a removal response (regardless of deletedCount).
# Used to record which files were in a failed folder's removal set.
extract_all_files() {
	local exec_response="$1"
	echo "$exec_response" | jq -r '.files[].filePath'
}

# After git restore, verify Prodcore still builds. If not, the repo was already
# broken before our removal — die rather than continue against a broken baseline.
verify_baseline_build() {
	tlog "  Verifying baseline build after git restore..."
	if ! build_prodcore; then
		die "Prodcore build is broken AFTER git restore — baseline was already broken. Stopping."
	fi
	tlog "  Baseline verified."
}

# Run build and write error file paths to a temp file (one per line).
# Returns 0 if build passed, 1 if failed.
# Caller reads error paths from $BUILD_ERROR_FILES_TMP.
BUILD_ERROR_FILES_TMP=$(mktemp)
build_prodcore_capturing_errors() {
	local build_log
	build_log=$(mktemp /tmp/xcodebuild-XXXXXX)

	xcodebuild \
		-project "$PRODCORE_PROJECT" \
		-scheme "$PRODCORE_SCHEME" \
		-destination "platform=macOS,arch=arm64" \
		-configuration Debug \
		-quiet \
		clean build \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		2>&1 | tee "$build_log"
	local exit_code="${PIPESTATUS[0]}"

	# Extract unique file paths from error lines (filter macro expansion files)
	grep -E "error:" "$build_log" \
		| grep -v "^Binary file" \
		| grep -v "@__swiftmacro_" \
		| grep -oE "^[^:]+\.swift" \
		| sort -u \
		> "$BUILD_ERROR_FILES_TMP" || true

	if [[ "$exit_code" -ne 0 ]]; then
		# Check if ALL errors are macro-expansion (known false positive)
		local real_errors
		real_errors=$(grep -E "error:" "$build_log" | grep -v "^Binary file" | grep -v "@__swiftmacro_" || true)
		if [[ -z "$real_errors" ]]; then
			tlog "    (all errors in @__swiftmacro_ expansion files — known Periphery gap)"
			rm -f "$build_log"
			return 0
		fi
		tlog "    Build log: $build_log"
		grep -E "error:" "$build_log" | grep -v "^Binary file" | head -10 | while IFS= read -r line; do
			tlog "      $line"
		done
	else
		rm -f "$build_log"
	fi
	return "$exit_code"
}

# Try to salvage a folder's removals by iteratively restoring only files that
# caused build errors, then retrying the build.
#
# Strategy:
#   Round A: error files that are modified → restore them directly.
#   Round B: error files all at HEAD (unmodified) → the root cause is a
#            modified file that exports a symbol now missing. Restore modified
#            files one-at-a-time (binary search style isn't worth it here; just
#            try each one), rebuild after each restore until the error clears.
#
# Never gives up on the whole folder just because one round made no progress;
# keeps going until the build passes or truly nothing remains to restore.
#
# Sets SALVAGE_DELETED to the count of deletions kept, SALVAGE_RESTORED to
# list of restored file paths.
SALVAGE_DELETED=0
SALVAGE_RESTORED=()
salvage_build() {
	local folder="$1"
	local initial_deleted="$2"
	SALVAGE_DELETED="$initial_deleted"
	SALVAGE_RESTORED=()

	local round=0

	while true; do
		round=$((round + 1))
		tlog "  Salvage round $round: building..."

		if build_prodcore_capturing_errors; then
			tlog "  Salvage succeeded after $round round(s). Kept $SALVAGE_DELETED deletion(s)."
			return 0
		fi

		# Read error files
		local error_files=()
		while IFS= read -r fp; do
			[[ -n "$fp" ]] && error_files+=("$fp")
		done < "$BUILD_ERROR_FILES_TMP"

		if [[ ${#error_files[@]} -eq 0 ]]; then
			tlog "  Salvage: build failed but no error files identified — giving up."
			return 1
		fi

		# Phase A: restore error files that are actually modified
		tlog "  Salvage: ${#error_files[@]} error file(s) — checking for modified ones:"
		local restored_count=0
		for ef in "${error_files[@]}"; do
			if [[ "$ef" == "$PRODCORE_DIR/"* ]]; then
				local rel="${ef#$PRODCORE_DIR/}"
				if git -C "$PRODCORE_DIR" diff --name-only HEAD -- "$rel" | grep -q .; then
					tlog "    Restoring: $rel"
					git -C "$PRODCORE_DIR" checkout HEAD -- "$rel" 2>/dev/null || true
					SALVAGE_RESTORED+=("$ef")
					restored_count=$((restored_count + 1))
				else
					tlog "    Already at HEAD: $rel (not modified)"
				fi
			fi
		done

		if [[ $restored_count -gt 0 ]]; then
			SALVAGE_DELETED=$(git -C "$PRODCORE_DIR" diff HEAD --name-only 2>/dev/null | wc -l | tr -d ' ')
			tlog "  Salvage: $restored_count file(s) restored. Remaining modified: $SALVAGE_DELETED"
			if [[ "$SALVAGE_DELETED" -eq 0 ]]; then
				tlog "  Salvage: nothing left to keep."
				return 1
			fi
			# Loop back — rebuild with restored files
			continue
		fi

		# Phase B: all error files are unmodified — the broken symbol was removed
		# from a modified file. Parse the missing symbol names from errors, grep
		# the modified files to find which ones define those symbols, restore those.
		tlog "  Salvage: all error files at HEAD — grepping modified files for missing symbols..."

		local modified_files=()
		while IFS= read -r rel; do
			[[ -n "$rel" ]] && modified_files+=("$rel")
		done < <(git -C "$PRODCORE_DIR" diff --name-only HEAD 2>/dev/null)

		if [[ ${#modified_files[@]} -eq 0 ]]; then
			tlog "  Salvage: no modified files remain — giving up."
			return 1
		fi

		# Parse error messages from the last build log into structured (type, member) pairs.
		# Three error patterns:
		#   1. "cannot find 'Foo' in scope" / "cannot find type 'Foo'" → top-level symbol Foo
		#   2. "type 'Bar' has no member 'foo'" → member foo on type Bar
		#   3. "uses an internal type" / "public ... internal type" → type visibility issue;
		#      the unmodified file references something that became internal — find which
		#      modified file now lacks a public declaration for that symbol.
		local last_log
		last_log=$(ls -t /tmp/xcodebuild-* 2>/dev/null | head -1)
		local log_src="${last_log:-$BUILD_ERROR_FILES_TMP}"

		# (type, member) pairs: TYPE="" means top-level search
		# Format: "TYPE\tMEMBER" — TYPE empty for top-level
		local search_pairs=()

		# Pattern 1: cannot find 'Foo' → top-level Foo
		while IFS= read -r sym; do
			[[ -n "$sym" ]] && search_pairs+=("	$sym")
		done < <(grep -oE "cannot find (type )?'[^']+'" "$log_src" \
			| grep -oE "'[^']+'" | tr -d "'" | sort -u 2>/dev/null || true)

		# Pattern 2: type 'Bar' has no member 'foo' → search for foo inside Bar
		while IFS= read -r pair; do
			[[ -n "$pair" ]] && search_pairs+=("$pair")
		done < <(grep -oE "type '[^']+' has no member '[^']+'" "$log_src" 2>/dev/null \
			| sed "s/type '\\([^']*\\)' has no member '\\([^']*\\)'/\\1	\\2/" \
			| sort -u || true)

		# Pattern 3: "cannot be declared public because its parameter/type uses an internal type"
		# The error message doesn't name the type, so read the referenced source line and extract
		# PascalCase type names from it, then search modified files for those types.
		# Filter out common Swift/SwiftUI builtins to avoid false matches.
		local -a builtin_types=(String Int Bool Double Float CGFloat UUID URL Data Date
			View AnyView ViewBuilder Body Content Never Void Optional Array Dictionary Set
			Binding State StateObject ObservedObject EnvironmentObject Published Observable
			ObservableObject Equatable Hashable Identifiable Sendable Codable CaseIterable
			AnyHashable AnyObject NSObject NSCopying Error LocalizedError)
		while IFS= read -r err_loc; do
			local err_file err_line
			err_file=$(echo "$err_loc" | cut -d: -f1)
			err_line=$(echo "$err_loc" | cut -d: -f2)
			if [[ -f "$err_file" && "$err_line" =~ ^[0-9]+$ ]]; then
				local source_line
				source_line=$(sed -n "${err_line}p" "$err_file" 2>/dev/null || true)
				# Extract PascalCase identifiers (potential type names), skip builtins
				while IFS= read -r typename; do
					[[ -z "$typename" ]] && continue
					local is_builtin=false
					for bt in "${builtin_types[@]}"; do
						[[ "$typename" == "$bt" ]] && is_builtin=true && break
					done
					[[ "$is_builtin" == false ]] && search_pairs+=("	$typename")
				done < <(echo "$source_line" | grep -oE '\b[A-Z][A-Za-z0-9]+\b' | sort -u || true)
			fi
		done < <(grep -oE '[^[:space:]]+:[0-9]+:[0-9]+: error: (initializer|property|method|subscript|func) cannot be declared public because its (parameter|type) uses an internal type' "$log_src" 2>/dev/null \
			| grep -oE '^[^:]+:[0-9]+' | sort -u || true)

		# Pattern 5: "requires that 'X' conform to 'Y'" → extract both X and Y
		while IFS= read -r raw_type; do
			[[ -z "$raw_type" ]] && continue
			local is_builtin=false
			for bt in String Int Bool Double Float CGFloat UUID URL Data Date \
				View AnyView ViewBuilder Body Content Never Void Optional Array Dictionary Set \
				Binding State StateObject ObservedObject EnvironmentObject Published Observable \
				ObservableObject Equatable Hashable Identifiable Sendable Codable CaseIterable \
				AnyHashable AnyObject NSObject NSCopying Error LocalizedError; do
				[[ "$raw_type" == "$bt" ]] && is_builtin=true && break
			done
			[[ "$is_builtin" == false ]] && search_pairs+=("	$raw_type")
		done < <(grep -oE "requires that '[^']+' conform to '[^']+'" "$log_src" 2>/dev/null \
			| grep -oE "'[^']+'" | tr -d "'" | sort -u || true)

		# Pattern 4: "cannot convert value of type 'X'" or "argument type 'X' does not conform"
		# or "value of type 'X' has no member" → extract X (strip array/optional wrappers)
		while IFS= read -r raw_type; do
			[[ -z "$raw_type" ]] && continue
			# Strip leading [ and trailing ] (array), ? (optional)
			local stripped_type
			stripped_type="${raw_type#\[}"
			stripped_type="${stripped_type%\]}"
			stripped_type="${stripped_type%\?}"
			[[ -z "$stripped_type" ]] && continue
			local is_builtin=false
			for bt in String Int Bool Double Float CGFloat UUID URL Data Date \
				View AnyView ViewBuilder Body Content Never Void Optional Array Dictionary Set \
				Binding State StateObject ObservedObject EnvironmentObject Published Observable \
				ObservableObject Equatable Hashable Identifiable Sendable Codable CaseIterable \
				AnyHashable AnyObject NSObject NSCopying Error LocalizedError; do
				[[ "$stripped_type" == "$bt" ]] && is_builtin=true && break
			done
			[[ "$is_builtin" == false ]] && search_pairs+=("	$stripped_type")
		done < <(grep -oE "error: (cannot convert value of type|argument type|value of type) '[^']+'" "$log_src" 2>/dev/null \
			| grep -oE "'[^']+'" | tr -d "'" | sort -u || true)

		if [[ ${#search_pairs[@]} -eq 0 ]]; then
			tlog "  Salvage: could not extract symbol names from errors — giving up."
			return 1
		fi

		# Log what we're looking for
		local pair_display=()
		for p in "${search_pairs[@]}"; do
			local ptype pmember
			ptype=$(echo "$p" | cut -f1)
			pmember=$(echo "$p" | cut -f2)
			if [[ -n "$ptype" ]]; then
				pair_display+=("$ptype.$pmember")
			else
				pair_display+=("$pmember")
			fi
		done
		tlog "  Salvage: searching for: ${pair_display[*]}"

		# For each (type, member) pair, search modified files' HEAD versions
		local candidates_to_restore=()
		for p in "${search_pairs[@]}"; do
			local ptype pmember
			ptype=$(echo "$p" | cut -f1)
			pmember=$(echo "$p" | cut -f2)
			[[ -z "$pmember" ]] && continue

			local found=false
			for rel in "${modified_files[@]}"; do
				local head_content
				head_content=$(git -C "$PRODCORE_DIR" show "HEAD:$rel" 2>/dev/null) || continue

				if [[ -n "$ptype" ]]; then
					# Member search: find file containing type Bar AND member foo.
					# For dotted type names (e.g. Foo.Bar.Baz), use only the last component for
					# the struct/class/enum search since nested types use their short name.
					local ptype_last
					ptype_last="${ptype##*.}"
					if echo "$head_content" | grep -qE "(struct|class|enum|extension)[[:space:]]+$ptype_last([[:space:](<:{]|$)" && \
					   echo "$head_content" | grep -qE "(func|var|let|static)[[:space:]]+(var |let |func )*$pmember([[:space:](<:=]|$)"; then
						candidates_to_restore+=("$rel")
						tlog "    Found '$ptype.$pmember' in: $rel"
						found=true
						break
					fi
				else
					# Top-level search: find declaration of pmember
					if echo "$head_content" | grep -qE "(struct|class|enum|protocol|func|var|let|typealias|extension)[[:space:]]+$pmember([[:space:](<:{]|$)"; then
						candidates_to_restore+=("$rel")
						tlog "    Found '$pmember' in: $rel"
						found=true
						break
					fi
				fi
			done
			if [[ "$found" == false ]]; then
				tlog "    Not found in modified files: ${ptype:+$ptype.}$pmember"
			fi
		done

		# Deduplicate candidates
		local unique_candidates=()
		while IFS= read -r c; do
			[[ -n "$c" ]] && unique_candidates+=("$c")
		done < <(printf '%s\n' "${candidates_to_restore[@]}" | sort -u)

		if [[ ${#unique_candidates[@]} -eq 0 ]]; then
			tlog "  Salvage: no modified files define the missing symbols — giving up."
			return 1
		fi

		tlog "  Salvage: restoring ${#unique_candidates[@]} root-cause file(s):"
		for rel in "${unique_candidates[@]}"; do
			tlog "    Restoring: $rel"
			git -C "$PRODCORE_DIR" checkout HEAD -- "$rel" 2>/dev/null || true
			SALVAGE_RESTORED+=("$PRODCORE_DIR/$rel")
		done

		SALVAGE_DELETED=$(git -C "$PRODCORE_DIR" diff HEAD --name-only 2>/dev/null | wc -l | tr -d ' ')
		tlog "  Salvage: ${#unique_candidates[@]} root-cause file(s) restored. Remaining modified: $SALVAGE_DELETED"

		if [[ "$SALVAGE_DELETED" -eq 0 ]]; then
			tlog "  Salvage: nothing left to keep."
			return 1
		fi
		# Loop — rebuild with root-cause files restored
	done
}

# Build commit message summarizing what was removed/changed.
# Reads the execute_removal response and git diff to produce a concise message.
build_commit_message() {
	local folder="$1"
	local exec_response="$2"
	local total_deleted="$3"

	# Get a summary of changed symbols from git diff --stat
	local diff_summary
	diff_summary=$(git -C "$PRODCORE_DIR" diff --cached --stat 2>/dev/null | tail -1 || true)

	# Get file names that changed (just basenames, up to 5)
	local changed_files
	changed_files=$(git -C "$PRODCORE_DIR" diff --cached --name-only 2>/dev/null \
		| xargs -I{} basename {} .swift \
		| head -5 \
		| tr '\n' ', ' \
		| sed 's/, $//' || true)

	local msg="Remove unused code from $folder: $total_deleted deletion(s)"
	if [[ -n "$changed_files" ]]; then
		msg="$msg ($changed_files)"
	fi
	echo "$msg"
}

# Verify the Prodcore git branch is the required cleanup branch.
verify_branch() {
	local current_branch
	current_branch=$(git -C "$PRODCORE_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
	if [[ "$current_branch" != "$REQUIRED_BRANCH" ]]; then
		die "Prodcore is on branch '$current_branch', not '$REQUIRED_BRANCH'. Switch to $REQUIRED_BRANCH before using --commit."
	fi
}

# ──────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────

main() {
	# Open fd 3 → terminal so tlog() can write there even inside $(...) subshells.
	exec 3>&1

	# Initialize report file
	echo "Treeswift Unused Code Cleanup — $(date)" > "$REPORT_FILE"
	echo "" >> "$REPORT_FILE"
	tlog "Report: $REPORT_FILE"
	tlog "Progress file: $PROGRESS_FILE"

	if [[ "$DRY_RUN" == true ]]; then
		tlog "DRY-RUN MODE: using preview endpoint; no files will be modified."
	fi

	# Verify branch before doing any work (--commit only)
	if [[ "$AUTO_COMMIT" == true ]]; then
		verify_branch
		tlog "Branch verified: $REQUIRED_BRANCH"
	fi

	# ── Progress file ──────────────────────────────────────
	if [[ "$RESET_PROGRESS" == true ]]; then
		rm -f "$PROGRESS_FILE"
		tlog "Progress file cleared (--reset-progress)."
	fi
	progress_load

	# ── Phase 1: Launch / connect ──────────────────────────
	if [[ "$SKIP_LAUNCH" == true ]]; then
		tlog "Skipping launch (--skip-launch). Checking server..."
		curl_get "$BASE_URL/status" > /dev/null
		tlog "Server is reachable."
	else
		if curl -s --connect-timeout 2 "$BASE_URL/status" > /dev/null 2>&1; then
			tlog "Treeswift already running on port $PORT."
		else
			launch_treeswift
		fi
	fi

	# ── Phase 2: Config + optional scan ───────────────────
	CONFIG_ID=$(get_or_create_config)

	if [[ "$SKIP_SCAN" == true ]]; then
		tlog "Skipping scan (--skip-scan). Using existing results."
	else
		log_section "Starting Prodcore scan (this may take several minutes)..."
		start_scan "$CONFIG_ID"
		tlog "Scan started."
		wait_for_scan_with_heartbeat "$CONFIG_ID"
	fi

	# ── Phase 3: Fetch periphery tree ─────────────────────
	tlog "Fetching periphery tree..."
	TREE_JSON=$(get_periphery_tree "$CONFIG_ID") \
		|| die "Failed to fetch periphery tree (HTTP error — check server logs)"

	# Detect single-root wrapper (e.g., a top-level "Prodcore" folder containing
	# the real source folders) and descend one level if present.
	root_count=$(echo "$TREE_JSON" | jq '[.[] | select(.type=="folder")] | length')
	if [[ "$root_count" -eq 1 ]]; then
		root_name=$(echo "$TREE_JSON" | jq -r 'first(.[] | select(.type=="folder") | .name)')
		tlog "Single root folder '$root_name' detected — using its children as top-level."
		TREE_JSON=$(echo "$TREE_JSON" | jq 'first(.[] | select(.type=="folder") | .children)')
	fi

	ALL_FOLDERS=()
	while IFS= read -r folder_name; do
		[[ -n "$folder_name" ]] && ALL_FOLDERS+=("$folder_name")
	done < <(echo "$TREE_JSON" | jq -r '.[] | select(.type=="folder") | .name')

	if [[ ${#ALL_FOLDERS[@]} -eq 0 ]]; then
		die "No folders found in periphery tree. Is the scan producing results?"
	fi

	tlog "Top-level folders with warnings: ${ALL_FOLDERS[*]}"

	if [[ ${#FOLDER_FILTER[@]} -gt 0 ]]; then
		FOLDERS=("${FOLDER_FILTER[@]}")
		tlog "Filtering to: ${FOLDERS[*]}"
	else
		FOLDERS=("${ALL_FOLDERS[@]}")
	fi

	# ── Phase 4: Folder-by-folder cleanup loop ────────────
	FOLDERS_CLEANED=()
	FOLDERS_SKIPPED=()
	FOLDERS_EMPTY=()
	FOLDERS_RESUMED=()
	TOTAL_DELETED=0

	for FOLDER in "${FOLDERS[@]}"; do
		log_section "FOLDER: $FOLDER"

		# Skip folders already recorded in progress file
		existing_status=$(progress_folder_done "$FOLDER")
		if [[ -n "$existing_status" ]]; then
			tlog "  [RESUME] Already processed ($existing_status) — skipping."
			FOLDERS_RESUMED+=("$FOLDER ($existing_status)")
			continue
		fi

		if [[ "$FOLDER" == */* ]]; then
			NODE_IDS=$(collect_file_ids_by_path "$TREE_JSON" "$FOLDER")
		else
			NODE_IDS=$(collect_file_ids "$TREE_JSON" "$FOLDER")
		fi
		FILE_COUNT=$(echo "$NODE_IDS" | jq 'length')

		if [[ "$FILE_COUNT" -eq 0 ]]; then
			tlog "  No files with warnings in '$FOLDER' — skipping."
			FOLDERS_EMPTY+=("$FOLDER")
			progress_record_folder "$FOLDER" "empty"
			continue
		fi

		tlog "  Files with warnings: $FILE_COUNT"

		# ── Dry-run branch ──────────────────────────────
		if [[ "$DRY_RUN" == true ]]; then
			tlog "  [DRY-RUN] Running preview (skipReferenced)..."
			PREVIEW_RESP=$(preview_removal "$CONFIG_ID" "$NODE_IDS" "skipReferenced")
			PREVIEW_DEL=$(echo "$PREVIEW_RESP" | jq '.totalDeletable // 0')
			PREVIEW_NONDEL=$(echo "$PREVIEW_RESP" | jq '.totalNonDeletable // 0')
			tlog "  [DRY-RUN] Would delete: $PREVIEW_DEL  (non-deletable: $PREVIEW_NONDEL)"
			TOTAL_DELETED=$((TOTAL_DELETED + PREVIEW_DEL))
			FOLDERS_CLEANED+=("$FOLDER (+$PREVIEW_DEL, dry-run)")
			continue
		fi

		# ── Execute removal ──────────────────────────────
		tlog "  Executing removal (strategy=skipReferenced, files=$FILE_COUNT)..."
		(while true; do sleep 30; tlog "  ... still removing ..."; done) &
		hb_removal=$!
		EXEC_RESP=$(execute_removal "$CONFIG_ID" "$NODE_IDS" "skipReferenced")
		kill "$hb_removal" 2>/dev/null; wait "$hb_removal" 2>/dev/null || true

		DELETED=$(echo "$EXEC_RESP" | jq '.totalDeleted // 0')
		EXEC_ERRORS=$(echo "$EXEC_RESP" | jq '.errors | length')

		tlog "  Deleted: $DELETED  Errors: $EXEC_ERRORS"

		if [[ "$EXEC_ERRORS" -gt 0 ]]; then
			echo "$EXEC_RESP" | jq -r '.errors[]' | while IFS= read -r err; do
				tlog "  API Error: $err"
			done
		fi

		if [[ "$DELETED" -eq 0 ]]; then
			tlog "  Nothing was deleted — no build needed."
			FOLDERS_EMPTY+=("$FOLDER (0 deletions)")
			progress_record_folder "$FOLDER" "empty"
			continue
		fi

		# Collect modified file paths for commit and progress tracking
		MODIFIED_FILES=()
		while IFS= read -r fpath; do
			[[ -n "$fpath" ]] && MODIFIED_FILES+=("$fpath")
		done < <(extract_modified_files "$EXEC_RESP")

		ALL_TOUCHED_FILES=()
		while IFS= read -r fpath; do
			[[ -n "$fpath" ]] && ALL_TOUCHED_FILES+=("$fpath")
		done < <(extract_all_files "$EXEC_RESP")

		tlog "  Modified files (${#MODIFIED_FILES[@]}):"
		for mf in "${MODIFIED_FILES[@]}"; do
			tlog "    $mf"
		done

		# ── Build verification with salvage ─────────────
		tlog "  Building Prodcore (initial attempt)..."
		if build_prodcore_capturing_errors; then
			KEPT_DELETED="$DELETED"
			KEPT_RESTORED=()
		else
			# Initial build failed — try salvage (restore only error files, retry)
			tlog "  Initial build FAILED — attempting salvage..."
			if salvage_build "$FOLDER" "$DELETED"; then
				KEPT_DELETED="$SALVAGE_DELETED"
				KEPT_RESTORED=("${SALVAGE_RESTORED[@]+"${SALVAGE_RESTORED[@]}"}")
				tlog "  Salvage PASSED. Kept $KEPT_DELETED deletion(s), restored ${#KEPT_RESTORED[@]} file(s)."
			else
				# Salvage failed — restore any remaining modified files
				tlog "  Salvage FAILED — restoring remaining modified files."
				local remaining_modified=()
				while IFS= read -r rel; do
					[[ -n "$rel" ]] && remaining_modified+=("$rel")
				done < <(git -C "$PRODCORE_DIR" diff --name-only HEAD 2>/dev/null)
				for rel in "${remaining_modified[@]+"${remaining_modified[@]}"}"; do
					git -C "$PRODCORE_DIR" checkout HEAD -- "$rel" 2>/dev/null || true
				done
				verify_baseline_build
				tlog "  SKIPPED: $FOLDER — could not salvage any removals"
				FOLDERS_SKIPPED+=("$FOLDER")
				progress_record_folder "$FOLDER" "skipped"
				progress_record_skipped_files "$FOLDER" "${ALL_TOUCHED_FILES[@]}"
				continue
			fi
		fi

		# Build passed (either directly or via salvage)
		tlog "  Build PASSED. $KEPT_DELETED deletion(s) kept."
		FOLDERS_CLEANED+=("$FOLDER (+$KEPT_DELETED)")
		TOTAL_DELETED=$((TOTAL_DELETED + KEPT_DELETED))
		progress_record_folder "$FOLDER" "cleaned"

		# Record salvaged-out files as skipped
		if [[ ${#KEPT_RESTORED[@]} -gt 0 ]]; then
			progress_record_skipped_files "$FOLDER" "${KEPT_RESTORED[@]}"
		fi

		# Optional auto-commit
		if [[ "$AUTO_COMMIT" == true ]]; then
			tlog "  Staging changes for commit..."
			git -C "$PRODCORE_DIR" add -A

			# Paranoia: verify build one more time before committing
			tlog "  Pre-commit build verification..."
			if ! build_prodcore_capturing_errors; then
				tlog "  WARNING: pre-commit build failed — full restore, skipping commit."
				git -C "$PRODCORE_DIR" reset HEAD
				git_reset_prodcore
				verify_baseline_build
				progress_record_folder "$FOLDER" "skipped"
				progress_record_skipped_files "$FOLDER" "${ALL_TOUCHED_FILES[@]}"
				FOLDERS_SKIPPED+=("$FOLDER (pre-commit verification failed)")
				continue
			fi

			COMMIT_MSG=$(build_commit_message "$FOLDER" "$EXEC_RESP" "$KEPT_DELETED")
			git -C "$PRODCORE_DIR" commit -m "$COMMIT_MSG"
			tlog "  Committed: $COMMIT_MSG"
		fi
	done

	# ── Phase 5: Summary ──────────────────────────────────
	log_section "CLEANUP SUMMARY"
	tlog ""

	tlog "Folders cleaned (${#FOLDERS_CLEANED[@]}):"
	for f in "${FOLDERS_CLEANED[@]+"${FOLDERS_CLEANED[@]}"}"; do
		tlog "  CLEANED  $f"
	done

	tlog ""
	tlog "Folders skipped — build failed, changes restored (${#FOLDERS_SKIPPED[@]}):"
	for f in "${FOLDERS_SKIPPED[@]+"${FOLDERS_SKIPPED[@]}"}"; do
		tlog "  SKIPPED  $f"
	done

	tlog ""
	tlog "Folders with no warnings or zero deletions (${#FOLDERS_EMPTY[@]}):"
	for f in "${FOLDERS_EMPTY[@]+"${FOLDERS_EMPTY[@]}"}"; do
		tlog "  EMPTY    $f"
	done

	tlog ""
	tlog "Folders resumed from prior run (${#FOLDERS_RESUMED[@]}):"
	for f in "${FOLDERS_RESUMED[@]+"${FOLDERS_RESUMED[@]}"}"; do
		tlog "  RESUMED  $f"
	done

	tlog ""
	if [[ "$DRY_RUN" == true ]]; then
		tlog "Total would-be deletions (dry-run): $TOTAL_DELETED"
	else
		tlog "Total actual deletions this run: $TOTAL_DELETED"
	fi
	tlog ""
	tlog "Progress file: $PROGRESS_FILE"
	tlog "Full report:   $REPORT_FILE"

	if [[ ${#FOLDERS_SKIPPED[@]} -gt 0 ]]; then
		tlog ""
		tlog "Note: ${#FOLDERS_SKIPPED[@]} folder(s) skipped due to build failures."
		tlog "Affected files recorded in $PROGRESS_FILE under 'skippedFiles'."
		tlog "These likely contain false positives (e.g. @Observable macro references)."
	fi
}

main "$@"
