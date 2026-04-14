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
#   --skip-build       Skip the pre-scan Prodcore build
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
SKIP_BUILD=false
AUTO_COMMIT=false
DRY_RUN=false
RESET_PROGRESS=false
FOLDER_FILTER=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--skip-launch)    SKIP_LAUNCH=true;    shift ;;
		--skip-scan)      SKIP_SCAN=true;      shift ;;
		--skip-build)     SKIP_BUILD=true;     shift ;;
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
#   get_or_create_config, build_prodcore_for_index, start_scan,
#   wait_for_scan, get_periphery_tree, collect_file_ids,
#   curl_post_resilient, preview_removal, execute_removal,
#   build_prodcore, git_reset_prodcore, wait_for_scan_with_heartbeat
# ──────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source <(grep -v '^main "\$@"' "$SCRIPT_DIR/integration-test-removal.sh")

# Declare our own REPORT_FILE AFTER source so the sourced script's global
# assignments don't clobber ours (log() references $REPORT_FILE by name at
# call time, so this is safe as long as we set it before the first log() call).
REPORT_FILE="/tmp/treeswift-cleanup-$(date +%Y%m%d-%H%M%S).txt"

# ──────────────────────────────────────────────────────────
# PROGRESS PERSISTENCE HELPERS
# ──────────────────────────────────────────────────────────

progress_load() {
	if [[ -f "$PROGRESS_FILE" ]]; then
		log "Resuming from progress file: $PROGRESS_FILE"
		log "  (use --reset-progress to start fresh)"
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
	log "  Verifying baseline build after git restore..."
	if ! build_prodcore; then
		die "Prodcore build is broken AFTER git restore — baseline was already broken. Stopping."
	fi
	log "  Baseline verified."
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
	# Open fd 3 → terminal so log() can write there even inside $(...) subshells.
	exec 3>&1

	# Initialize report file
	echo "Treeswift Unused Code Cleanup — $(date)" > "$REPORT_FILE"
	echo "" >> "$REPORT_FILE"
	log "Report: $REPORT_FILE"
	log "Progress file: $PROGRESS_FILE"

	if [[ "$DRY_RUN" == true ]]; then
		log "DRY-RUN MODE: using preview endpoint; no files will be modified."
	fi

	# Verify branch before doing any work (--commit only)
	if [[ "$AUTO_COMMIT" == true ]]; then
		verify_branch
		log "Branch verified: $REQUIRED_BRANCH"
	fi

	# ── Progress file ──────────────────────────────────────
	if [[ "$RESET_PROGRESS" == true ]]; then
		rm -f "$PROGRESS_FILE"
		log "Progress file cleared (--reset-progress)."
	fi
	progress_load

	# ── Phase 1: Launch / connect ──────────────────────────
	if [[ "$SKIP_LAUNCH" == true ]]; then
		log "Skipping launch (--skip-launch). Checking server..."
		curl_get "$BASE_URL/status" > /dev/null
		log "Server is reachable."
	else
		if curl -s --connect-timeout 2 "$BASE_URL/status" > /dev/null 2>&1; then
			log "Treeswift already running on port $PORT."
		else
			launch_treeswift
		fi
	fi

	# ── Phase 2: Config + optional scan ───────────────────
	CONFIG_ID=$(get_or_create_config)

	if [[ "$SKIP_SCAN" == true ]]; then
		log "Skipping scan (--skip-scan). Using existing results."
	else
		if [[ "$SKIP_BUILD" == true ]]; then
			log "Skipping pre-scan build (--skip-build)."
		else
			build_prodcore_for_index
		fi
		log_section "Starting Prodcore scan (this may take several minutes)..."
		start_scan "$CONFIG_ID"
		log "Scan started."
		wait_for_scan_with_heartbeat "$CONFIG_ID"
	fi

	# ── Phase 3: Fetch periphery tree ─────────────────────
	log "Fetching periphery tree..."
	TREE_JSON=$(get_periphery_tree "$CONFIG_ID") \
		|| die "Failed to fetch periphery tree (HTTP error — check server logs)"

	# Detect single-root wrapper (e.g., a top-level "Prodcore" folder containing
	# the real source folders) and descend one level if present.
	root_count=$(echo "$TREE_JSON" | jq '[.[] | select(.type=="folder")] | length')
	if [[ "$root_count" -eq 1 ]]; then
		root_name=$(echo "$TREE_JSON" | jq -r 'first(.[] | select(.type=="folder") | .name)')
		log "Single root folder '$root_name' detected — using its children as top-level."
		TREE_JSON=$(echo "$TREE_JSON" | jq 'first(.[] | select(.type=="folder") | .children)')
	fi

	ALL_FOLDERS=()
	while IFS= read -r folder_name; do
		[[ -n "$folder_name" ]] && ALL_FOLDERS+=("$folder_name")
	done < <(echo "$TREE_JSON" | jq -r '.[] | select(.type=="folder") | .name')

	if [[ ${#ALL_FOLDERS[@]} -eq 0 ]]; then
		die "No folders found in periphery tree. Is the scan producing results?"
	fi

	log "Top-level folders with warnings: ${ALL_FOLDERS[*]}"

	if [[ ${#FOLDER_FILTER[@]} -gt 0 ]]; then
		FOLDERS=("${FOLDER_FILTER[@]}")
		log "Filtering to: ${FOLDERS[*]}"
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
			log "  [RESUME] Already processed ($existing_status) — skipping."
			FOLDERS_RESUMED+=("$FOLDER ($existing_status)")
			continue
		fi

		NODE_IDS=$(collect_file_ids "$TREE_JSON" "$FOLDER")
		FILE_COUNT=$(echo "$NODE_IDS" | jq 'length')

		if [[ "$FILE_COUNT" -eq 0 ]]; then
			log "  No files with warnings in '$FOLDER' — skipping."
			FOLDERS_EMPTY+=("$FOLDER")
			progress_record_folder "$FOLDER" "empty"
			continue
		fi

		log "  Files with warnings: $FILE_COUNT"

		# ── Dry-run branch ──────────────────────────────
		if [[ "$DRY_RUN" == true ]]; then
			log "  [DRY-RUN] Running preview (skipReferenced)..."
			PREVIEW_RESP=$(preview_removal "$CONFIG_ID" "$NODE_IDS" "skipReferenced")
			PREVIEW_DEL=$(echo "$PREVIEW_RESP" | jq '.totalDeletable // 0')
			PREVIEW_NONDEL=$(echo "$PREVIEW_RESP" | jq '.totalNonDeletable // 0')
			log "  [DRY-RUN] Would delete: $PREVIEW_DEL  (non-deletable: $PREVIEW_NONDEL)"
			TOTAL_DELETED=$((TOTAL_DELETED + PREVIEW_DEL))
			FOLDERS_CLEANED+=("$FOLDER (+$PREVIEW_DEL, dry-run)")
			continue
		fi

		# ── Execute removal ──────────────────────────────
		log "  Executing removal (strategy=skipReferenced, files=$FILE_COUNT)..."
		(while true; do sleep 30; log "  ... still removing ..."; done) &
		hb_removal=$!
		EXEC_RESP=$(execute_removal "$CONFIG_ID" "$NODE_IDS" "skipReferenced")
		kill "$hb_removal" 2>/dev/null; wait "$hb_removal" 2>/dev/null || true

		DELETED=$(echo "$EXEC_RESP" | jq '.totalDeleted // 0')
		EXEC_ERRORS=$(echo "$EXEC_RESP" | jq '.errors | length')

		log "  Deleted: $DELETED  Errors: $EXEC_ERRORS"

		if [[ "$EXEC_ERRORS" -gt 0 ]]; then
			echo "$EXEC_RESP" | jq -r '.errors[]' | while IFS= read -r err; do
				log "  API Error: $err"
			done
		fi

		if [[ "$DELETED" -eq 0 ]]; then
			log "  Nothing was deleted — no build needed."
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

		log "  Modified files (${#MODIFIED_FILES[@]}):"
		for mf in "${MODIFIED_FILES[@]}"; do
			log "    $mf"
		done

		# ── Build verification ───────────────────────────
		log "  Building Prodcore..."
		BUILD_OK=true
		if ! build_prodcore; then
			BUILD_OK=false
		fi

		if [[ "$BUILD_OK" == true ]]; then
			# SUCCESS: record this folder as cleaned
			log "  Build PASSED. $DELETED deletion(s) kept."
			FOLDERS_CLEANED+=("$FOLDER (+$DELETED)")
			TOTAL_DELETED=$((TOTAL_DELETED + DELETED))
			progress_record_folder "$FOLDER" "cleaned"

			# Optional auto-commit
			if [[ "$AUTO_COMMIT" == true ]]; then
				log "  Staging changes for commit..."
				git -C "$PRODCORE_DIR" add -A

				# Paranoia: verify build one more time before committing
				log "  Pre-commit build verification..."
				if ! build_prodcore; then
					log "  WARNING: pre-commit build failed — restoring and skipping commit."
					git -C "$PRODCORE_DIR" reset HEAD
					git_reset_prodcore
					verify_baseline_build
					progress_record_folder "$FOLDER" "skipped"
					progress_record_skipped_files "$FOLDER" "${ALL_TOUCHED_FILES[@]}"
					FOLDERS_SKIPPED+=("$FOLDER (pre-commit build verification failed)")
					continue
				fi

				COMMIT_MSG=$(build_commit_message "$FOLDER" "$EXEC_RESP" "$DELETED")
				git -C "$PRODCORE_DIR" commit -m "$COMMIT_MSG"
				log "  Committed: $COMMIT_MSG"
			fi

		else
			# FAILURE: restore everything and verify we're back to a clean state
			log "  Build FAILED. Restoring Prodcore to HEAD..."
			git_reset_prodcore
			verify_baseline_build
			log "  SKIPPED: $FOLDER — build failed after removal"
			FOLDERS_SKIPPED+=("$FOLDER")
			progress_record_folder "$FOLDER" "skipped"
			progress_record_skipped_files "$FOLDER" "${ALL_TOUCHED_FILES[@]}"
		fi
	done

	# ── Phase 5: Summary ──────────────────────────────────
	log_section "CLEANUP SUMMARY"
	log ""

	log "Folders cleaned (${#FOLDERS_CLEANED[@]}):"
	for f in "${FOLDERS_CLEANED[@]+"${FOLDERS_CLEANED[@]}"}"; do
		log "  CLEANED  $f"
	done

	log ""
	log "Folders skipped — build failed, changes restored (${#FOLDERS_SKIPPED[@]}):"
	for f in "${FOLDERS_SKIPPED[@]+"${FOLDERS_SKIPPED[@]}"}"; do
		log "  SKIPPED  $f"
	done

	log ""
	log "Folders with no warnings or zero deletions (${#FOLDERS_EMPTY[@]}):"
	for f in "${FOLDERS_EMPTY[@]+"${FOLDERS_EMPTY[@]}"}"; do
		log "  EMPTY    $f"
	done

	log ""
	log "Folders resumed from prior run (${#FOLDERS_RESUMED[@]}):"
	for f in "${FOLDERS_RESUMED[@]+"${FOLDERS_RESUMED[@]}"}"; do
		log "  RESUMED  $f"
	done

	log ""
	if [[ "$DRY_RUN" == true ]]; then
		log "Total would-be deletions (dry-run): $TOTAL_DELETED"
	else
		log "Total actual deletions this run: $TOTAL_DELETED"
	fi
	log ""
	log "Progress file: $PROGRESS_FILE"
	log "Full report:   $REPORT_FILE"

	if [[ ${#FOLDERS_SKIPPED[@]} -gt 0 ]]; then
		log ""
		log "Note: ${#FOLDERS_SKIPPED[@]} folder(s) skipped due to build failures."
		log "Affected files recorded in $PROGRESS_FILE under 'skippedFiles'."
		log "These likely contain false positives (e.g. @Observable macro references)."
	fi
}

main "$@"
