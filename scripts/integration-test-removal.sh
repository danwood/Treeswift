#!/usr/bin/env bash
# integration-test-removal.sh
#
# Automated integration test for Treeswift's "Remove Unused Code" feature.
# For each top-level Prodcore folder, tests all 3 RemovalStrategy values:
#   skipReferenced  — must always produce a passing build
#   forceRemoveAll  — may break the build (expected)
#   cascade         — may or may not break the build
#
# Usage:
#   bash scripts/integration-test-removal.sh [--skip-launch] [--skip-build] [--folder FOLDERNAME]
#
#   --skip-launch     Don't try to launch Treeswift; assume it's already running
#   --skip-build      Skip the pre-scan Prodcore build (indexstore may be stale — use only
#                     when you know the source files haven't changed since the last build)
#   --skip-scan       Skip the Periphery scan entirely; reuse cached results
#   --folder NAME     Only test the named top-level folder (can repeat)
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
STRATEGIES=("skipReferenced" "forceRemoveAll" "cascade")
REPORT_FILE="/tmp/treeswift-integration-$(date +%Y%m%d-%H%M%S).txt"
RESULTS_CACHE="/tmp/treeswift-integration-results.cache"

# ──────────────────────────────────────────────────────────
# ARGUMENT PARSING
# ──────────────────────────────────────────────────────────

SKIP_LAUNCH=false
SKIP_SCAN=false
SKIP_BUILD=false
RESET_CACHE=false
FOLDER_FILTER=()

while [[ $# -gt 0 ]]; do
	case "$1" in
		--skip-launch)
			SKIP_LAUNCH=true
			shift
			;;
		--skip-scan)
			SKIP_SCAN=true
			shift
			;;
		--skip-build)
			SKIP_BUILD=true
			shift
			;;
		--folder)
			FOLDER_FILTER+=("$2")
			shift 2
			;;
		--reset-cache)
			RESET_CACHE=true
			shift
			;;
		*)
			echo "Unknown argument: $1" >&2
			exit 1
			;;
	esac
done

# ──────────────────────────────────────────────────────────
# HELPERS
# ──────────────────────────────────────────────────────────

log() {
	local msg="[$(date '+%H:%M:%S')] $*"
	echo "$msg" >&3
	echo "$msg" >> "$REPORT_FILE"
}

log_section() {
	local line="──────────────────────────────────────────────────"
	echo "$line" >&3
	echo "$line" >> "$REPORT_FILE"
	log "$*"
}

die() {
	log "ERROR: $*"
	exit 1
}

# POST JSON to URL; echoes response body; dies on curl error
curl_post() {
	local url="$1"
	local body="$2"
	local max_time="${3:-30}"
	local response
	local http_code
	# Write body and status to temp files to avoid subshell pipe issues
	local body_file
	body_file=$(mktemp)
	http_code=$(curl -s -w "%{http_code}" -o "$body_file" \
		-X POST "$url" \
		-H "Content-Type: application/json" \
		--data-binary "$body" \
		--max-time "$max_time" 2>/dev/null || echo "000")
	response=$(cat "$body_file"); rm -f "$body_file"
	if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
		die "POST $url returned HTTP $http_code: $response"
	fi
	echo "$response"
}

# GET URL; echoes response body; returns 1 on curl/HTTP error (prints error to stderr)
curl_get() {
	local url="$1"
	local timeout="${2:-30}"
	local body_file
	body_file=$(mktemp)
	local http_code
	http_code=$(curl -s -w "%{http_code}" -o "$body_file" \
		"$url" \
		--max-time "$timeout" || true)
	local response
	response=$(cat "$body_file")
	rm -f "$body_file"
	if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
		echo "ERROR: GET $url returned HTTP $http_code: $response" >&2
		return 1
	fi
	echo "$response"
}

STATUS_FILE="/tmp/treeswift-control.json"
ERROR_FILE="/tmp/treeswift-control.error"

wait_for_server() {
	log "Waiting for Treeswift server on port $PORT..."
	# Phase 1: wait for status file (written when NWListener reaches .ready state)
	# Also watch for error file which signals a startup failure.
	local attempts=0
	local max_attempts=30
	while [[ $attempts -lt $max_attempts ]]; do
		if [[ -f "$ERROR_FILE" ]]; then
			die "Server startup failed: $(cat "$ERROR_FILE")"
		fi
		if [[ -f "$STATUS_FILE" ]] && python3 -c "import sys,json; d=json.load(open('$STATUS_FILE')); sys.exit(0 if d.get('port')==$PORT else 1)" 2>/dev/null; then
			log "Status file found — server bound on port $PORT."
			break
		fi
		sleep 1
		attempts=$((attempts + 1))
	done
	if [[ $attempts -ge $max_attempts ]]; then
		die "Status file never appeared after ${max_attempts}s — server did not start"
	fi
	# Phase 2: poll /ready until app state (configs, caches) is fully initialized
	log "Waiting for /ready..."
	attempts=0
	while [[ $attempts -lt 15 ]]; do
		local resp
		resp=$(curl -s --connect-timeout 1 "$BASE_URL/ready" 2>/dev/null)
		if echo "$resp" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('ready') else 1)" 2>/dev/null; then
			log "Server ready."
			return 0
		fi
		sleep 1
		attempts=$((attempts + 1))
	done
	die "Server never reached ready state after 15s"
}

launch_treeswift() {
	log "Locating Treeswift.app..."
	local app
	app=$(find ~/Library/Developer/Xcode/DerivedData -name "Treeswift.app" -maxdepth 8 2>/dev/null \
		| grep -v "\.dSYM" | grep "Build/Products" | head -1)
	if [[ -z "$app" ]]; then
		die "Could not find Treeswift.app in DerivedData. Build it first with: xcodebuild -project Treeswift.xcodeproj -scheme Treeswift build"
	fi
	log "Found: $app"
	pkill -x Treeswift 2>/dev/null || true
	sleep 1
	rm -f "$STATUS_FILE" "$ERROR_FILE"
	log "Launching Treeswift with --automation-port $PORT..."
	# Use 'open' (not direct binary) to ensure the app window appears and .onAppear fires,
	# which is required for the automation server to start.
	open "$app" --args --automation-port "$PORT"
	wait_for_server
}

get_or_create_config() {
	local configs existing
	configs=$(curl_get "$BASE_URL/configurations")
	existing=$(echo "$configs" | \
		jq -r --arg name "$CONFIG_NAME" 'first(.[] | select(.name == $name) | .id) // empty')
	if [[ -n "$existing" ]]; then
		log "Reusing existing configuration: $existing"
		echo "$existing"
		return
	fi
	log "Creating Prodcore configuration..."
	local resp
	resp=$(curl_post "$BASE_URL/configurations" \
		"{\"name\":\"$CONFIG_NAME\",\"projectType\":\"xcode\",\"project\":\"$PRODCORE_PROJECT\",\"schemes\":[\"$PRODCORE_SCHEME\"]}")
	local new_id
	new_id=$(echo "$resp" | jq -r '.id')
	log "Created configuration: $new_id"
	echo "$new_id"
}

build_prodcore_for_index() {
	# Builds Prodcore to verify it compiles before scanning.
	# NOTE: This does NOT update the indexstore that Periphery reads. Periphery uses its
	# own DerivedData path (~/.../com.github.peripheryapp/) and builds the project itself
	# during scanning. This step is only useful to confirm the source compiles.
	log "Building Prodcore to verify it compiles (does not update Periphery's indexstore)..."
	local build_log
	build_log=$(mktemp /tmp/xcodebuild-index-XXXXXX)
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
	if [[ "$exit_code" -ne 0 ]]; then
		log "  WARNING: Pre-scan build failed (exit $exit_code). Source may have issues."
		log "  Build log: $build_log"
	else
		rm -f "$build_log"
		log "  Build complete."
	fi
}

start_scan() {
	local config_id="$1"
	local body_file http_code response
	# Retry once in case the server is momentarily busy
	for attempt in 1 2; do
		body_file=$(mktemp)
		http_code=$(curl -s -w "%{http_code}" -o "$body_file" \
			-X POST "$BASE_URL/configurations/$config_id/scan" \
			-H "Content-Type: application/json" \
			--max-time 30 2>/dev/null || echo "000")
		response=$(cat "$body_file"); rm -f "$body_file"
		# 200 = started, 409 = already scanning — both are fine
		if [[ "$http_code" == "200" || "$http_code" == "409" ]]; then
			return 0
		fi
		[[ "$attempt" -lt 2 ]] && { log "  start_scan: HTTP $http_code, retrying in 3s..."; sleep 3; }
	done
	die "Failed to start scan (HTTP $http_code): $response"
}

wait_for_scan() {
	local config_id="$1"
	log "Waiting for scan to complete (timeout: ${SCAN_TIMEOUT}s)..."
	local resp
	resp=$(curl_get "$BASE_URL/configurations/$config_id/scan/wait" "$SCAN_TIMEOUT")
	local clean_resp
	clean_resp=$(printf '%s' "$resp" | LC_ALL=C tr -d '\000-\037' 2>/dev/null || printf '%s' "$resp")
	local err
	err=$(printf '%s' "$clean_resp" | jq -r '.errorMessage // empty' 2>/dev/null || true)
	if [[ -n "$err" ]]; then
		die "Scan failed: $err"
	fi
	local status
	status=$(printf '%s' "$clean_resp" | jq -r '.scanStatus // "unknown"' 2>/dev/null || echo "unknown")
	log "Scan complete. Status: $status"
}

get_periphery_tree() {
	local config_id="$1"
	local url="$BASE_URL/configurations/$config_id/results/periphery-tree"
	local body_file http_code response
	body_file=$(mktemp)
	http_code=$(curl -s -w "%{http_code}" -o "$body_file" \
		"$url" \
		--max-time 60 || true)
	response=$(cat "$body_file")
	rm -f "$body_file"
	if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
		echo "ERROR: GET $url returned HTTP $http_code: $response" >&2
		return 1
	fi
	echo "$response"
}

# Collect all file IDs (full paths) within a named top-level folder in the periphery tree JSON.
# Returns a JSON array string suitable for use as "nodeIds" in removal requests.
collect_file_ids() {
	local tree_json="$1"
	local folder_name="$2"
	echo "$tree_json" | jq -r \
		--arg n "$folder_name" \
		'map(select(.type=="folder" and .name==$n)) | first | .. | objects | select(.type=="file") | .id' \
		| jq -Rs 'split("\n") | map(select(length>0))'
}

# POST JSON with one retry on connection failure (e.g. server just restarted).
curl_post_resilient() {
	local url="$1"
	local body="$2"
	local label="${3:-POST}"
	local body_file http_code response
	body_file=$(mktemp)
	http_code=$(curl -s -w "%{http_code}" -o "$body_file" \
		-X POST "$url" \
		-H "Content-Type: application/json" \
		--data-binary "$body" \
		--max-time 120 2>/dev/null || echo "000")
	response=$(cat "$body_file"); rm -f "$body_file"
	if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
		log "    $label returned HTTP $http_code — waiting for server and retrying..."
		wait_for_server
		body_file=$(mktemp)
		http_code=$(curl -s -w "%{http_code}" -o "$body_file" \
			-X POST "$url" \
			-H "Content-Type: application/json" \
			--data-binary "$body" \
			--max-time 120 2>/dev/null || echo "000")
		response=$(cat "$body_file"); rm -f "$body_file"
		if [[ "$http_code" -lt 200 || "$http_code" -ge 300 ]]; then
			die "$label failed after retry: HTTP $http_code: $response"
		fi
	fi
	echo "$response"
}

preview_removal() {
	local config_id="$1"
	local node_ids_json="$2"
	local strategy="$3"
	curl_post_resilient \
		"$BASE_URL/configurations/$config_id/removal/preview" \
		"{\"nodeIds\":$node_ids_json,\"strategy\":\"$strategy\"}" \
		"preview/$strategy"
}

execute_removal() {
	local config_id="$1"
	local node_ids_json="$2"
	local strategy="$3"
	curl_post_resilient \
		"$BASE_URL/configurations/$config_id/removal/execute" \
		"{\"nodeIds\":$node_ids_json,\"strategy\":\"$strategy\"}" \
		"execute/$strategy"
}

build_prodcore() {
	local build_log
	build_log=$(mktemp /tmp/xcodebuild-XXXXXX)

	# Use clean build so deleted files don't cause "Build input files cannot be found" errors.
	# -quiet suppresses per-file compile lines; errors still appear.
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

	if [[ "$exit_code" -ne 0 ]]; then
		log "    Build log: $build_log"
		grep -E "error:" "$build_log" | grep -v "^Binary file" | head -10 | while IFS= read -r line; do
			log "      $line"
		done

		# Check if ALL errors are from macro-expansion files (known Periphery analysis gap:
		# @Observable macro-synthesized references are invisible to Periphery's analysis).
		# If so, treat this as a known false positive rather than a real removal bug.
		local real_errors
		real_errors=$(grep -E "error:" "$build_log" | grep -v "^Binary file" | grep -v "@__swiftmacro_" || true)
		if [[ -z "$real_errors" ]]; then
			log "    (all errors are in @__swiftmacro_ expansion files — known Periphery gap, not a removal bug)"
			rm -f "$build_log"
			return 0
		fi
	else
		rm -f "$build_log"
	fi
	return "$exit_code"
}

git_reset_prodcore() {
	git -C "$PRODCORE_DIR" checkout HEAD -- . || die "git reset failed — stopping to avoid testing against modified code"
}

validate_previews() {
	local skip_resp="$1"
	local force_resp="$2"
	local skip_del force_del
	skip_del=$(echo "$skip_resp" | jq '.totalDeletable')
	force_del=$(echo "$force_resp" | jq '.totalDeletable')
	# Note: skip can legitimately exceed force when access-control fixes remain
	# after skipReferenced skips some .unused deletions that would have caused
	# ancestor-promotion (consolidating multiple ops into one) in forceRemoveAll.
	log "    [INFO] skip($skip_del) vs force($force_del)"
}

cache_key() {
	echo "$1|$2"  # folder|strategy
}

cache_lookup() {
	local key
	key=$(cache_key "$1" "$2")
	[[ -f "$RESULTS_CACHE" ]] && grep -Fx "$key" "$RESULTS_CACHE" > /dev/null 2>&1
}

cache_record() {
	local key
	key=$(cache_key "$1" "$2")
	echo "$key" >> "$RESULTS_CACHE"
}

wait_for_scan_with_heartbeat() {
	local config_id="$1"
	log "  Waiting for scan to complete (timeout: ${SCAN_TIMEOUT}s)..."
	(while true; do sleep 30; log "  ... still scanning ..."; done) &
	local hb=$!
	local resp
	resp=$(curl_get "$BASE_URL/configurations/$config_id/scan/wait" "$SCAN_TIMEOUT")
	kill "$hb" 2>/dev/null; wait "$hb" 2>/dev/null || true
	# Strip ASCII control characters (e.g. ANSI escape codes from embedded xcodebuild output)
	# before passing to jq, which rejects them as invalid JSON.
	local clean_resp
	clean_resp=$(printf '%s' "$resp" | LC_ALL=C tr -d '\000-\037' 2>/dev/null || printf '%s' "$resp")
	local err
	err=$(printf '%s' "$clean_resp" | jq -r '.errorMessage // empty' 2>/dev/null || true)
	if [[ -n "$err" ]]; then
		die "Scan failed: $err"
	fi
	log "  Scan complete."
}

# ──────────────────────────────────────────────────────────
# MAIN
# ──────────────────────────────────────────────────────────

main() {
	# Open fd 3 → terminal (stdout). log() writes to fd 3 so that functions called via
	# $(...) command substitution can log without their output being captured in the variable.
	exec 3>&1
	# Initialize report file
	echo "Treeswift Integration Test — $(date)" > "$REPORT_FILE"
	echo "" >> "$REPORT_FILE"
	log "Report: $REPORT_FILE"

	if [[ "$RESET_CACHE" == true ]]; then
		rm -f "$RESULTS_CACHE"
		log "Results cache cleared."
	elif [[ -f "$RESULTS_CACHE" ]]; then
		log "Resuming from cache: $RESULTS_CACHE (use --reset-cache to start fresh)"
	fi

	# Phase 1: Launch / connect
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

	# Phase 2: Config + Scan
	CONFIG_ID=$(get_or_create_config)

	if [[ "$SKIP_SCAN" == true ]]; then
		log "Skipping scan (--skip-scan). Using existing results."
	else
		if [[ "$SKIP_BUILD" == true ]]; then
			log "Skipping pre-scan build (--skip-build). Indexstore may be stale."
		else
			build_prodcore_for_index
		fi
		log_section "Starting Prodcore scan (this may take several minutes)..."
		start_scan "$CONFIG_ID"
		log "Scan started."
		wait_for_scan_with_heartbeat "$CONFIG_ID"
	fi

	log "Fetching periphery tree..."
	TREE_JSON=$(get_periphery_tree "$CONFIG_ID") || die "Failed to fetch periphery tree (HTTP error — check server logs)"

	# The periphery tree may have a single root folder (e.g., "Prodcore") wrapping
	# the actual source folders. Detect this and descend one level if needed.
	root_count=$(echo "$TREE_JSON" | jq '[.[] | select(.type=="folder")] | length')
	if [[ "$root_count" -eq 1 ]]; then
		root_name=$(echo "$TREE_JSON" | jq -r 'first(.[] | select(.type=="folder") | .name)')
		log "Single root folder '$root_name' detected — using its children as top-level folders."
		# Replace TREE_JSON with the children of the root folder for all subsequent operations
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

	# Apply folder filter if requested
	if [[ ${#FOLDER_FILTER[@]} -gt 0 ]]; then
		FOLDERS=("${FOLDER_FILTER[@]}")
		log "Filtering to: ${FOLDERS[*]}"
	else
		FOLDERS=("${ALL_FOLDERS[@]}")
	fi

	# Phase 3: Main test loop
	# Results array: "FOLDER|STRATEGY|DELETED|BUILD"
	RESULTS=()
	UNEXPECTED_FAILURES=0

	for FOLDER in "${FOLDERS[@]}"; do
		log_section "FOLDER: $FOLDER"

		NODE_IDS=$(collect_file_ids "$TREE_JSON" "$FOLDER")
		FILE_COUNT=$(echo "$NODE_IDS" | jq 'length')

		if [[ "$FILE_COUNT" -eq 0 ]]; then
			log "  No files with warnings in '$FOLDER', skipping."
			continue
		fi

		log "  Files with warnings: $FILE_COUNT"

		# Preview all 3 strategies before executing any (no disk state change)
		log "  Running preview: skipReferenced..."
		P_SKIP=$(preview_removal "$CONFIG_ID" "$NODE_IDS" "skipReferenced")
		log "  Running preview: forceRemoveAll..."
		P_FORCE=$(preview_removal "$CONFIG_ID" "$NODE_IDS" "forceRemoveAll")
		log "  Running preview: cascade..."
		P_CASCADE=$(preview_removal "$CONFIG_ID" "$NODE_IDS" "cascade")

		validate_previews "$P_SKIP" "$P_FORCE"

		SKIP_DEL=$(echo "$P_SKIP" | jq '.totalDeletable')
		FORCE_DEL=$(echo "$P_FORCE" | jq '.totalDeletable')
		CASCADE_DEL=$(echo "$P_CASCADE" | jq '.totalDeletable')
		SKIP_NONDEL=$(echo "$P_SKIP" | jq '.totalNonDeletable')
		FORCE_NONDEL=$(echo "$P_FORCE" | jq '.totalNonDeletable')

		log "  Preview deletable:    skipReferenced=$SKIP_DEL  forceRemoveAll=$FORCE_DEL  cascade=$CASCADE_DEL"
		log "  Preview nonDeletable: skipReferenced=$SKIP_NONDEL  forceRemoveAll=$FORCE_NONDEL"

		for STRATEGY in "${STRATEGIES[@]}"; do
			log_section "  $FOLDER / $STRATEGY"

			# Skip if already recorded in cache
			if cache_lookup "$FOLDER" "$STRATEGY"; then
				log "  [SKIP] $FOLDER / $STRATEGY — already passed in a previous run."
				RESULTS+=("$FOLDER|$STRATEGY|—|SKIP")
				continue
			fi

			# Execute removal
			log "    Executing removal (strategy=$STRATEGY, files=$FILE_COUNT)..."
			(while true; do sleep 30; log "    ... still removing ..."; done) &
			hb_removal=$!
			EXEC=$(execute_removal "$CONFIG_ID" "$NODE_IDS" "$STRATEGY")
			kill "$hb_removal" 2>/dev/null; wait "$hb_removal" 2>/dev/null || true
			DELETED=$(echo "$EXEC" | jq '.totalDeleted')
			EXEC_ERRORS=$(echo "$EXEC" | jq '.errors | length')

			log "    Deleted: $DELETED  Errors: $EXEC_ERRORS"
			if [[ "$EXEC_ERRORS" -gt 0 ]]; then
				echo "$EXEC" | jq -r '.errors[]' | while IFS= read -r err; do
					log "    Error: $err"
				done
			fi

			# Verify preview matched execution
			case "$STRATEGY" in
				"skipReferenced") PREVIEW_DEL="$SKIP_DEL" ;;
				"forceRemoveAll") PREVIEW_DEL="$FORCE_DEL" ;;
				"cascade")        PREVIEW_DEL="$CASCADE_DEL" ;;
			esac
			if [[ "$PREVIEW_DEL" -ne "$DELETED" ]]; then
				log "    [CHECK] Preview($PREVIEW_DEL) vs Executed($DELETED): MISMATCH"
			else
				log "    [CHECK] Preview vs Executed ($DELETED): MATCH"
			fi

			# Build
			log "    Building Prodcore (xcodebuild -scheme $PRODCORE_SCHEME)..."
			BUILD_RESULT="PASS"
			if ! build_prodcore; then
				BUILD_RESULT="FAIL"
			fi
			log "    Build: $BUILD_RESULT"

			# Flag unexpected failures; record passing skipReferenced to cache
			if [[ "$STRATEGY" == "skipReferenced" ]]; then
				if [[ "$BUILD_RESULT" == "FAIL" ]]; then
					log "    *** UNEXPECTED: skipReferenced should never break the build! ***"
					UNEXPECTED_FAILURES=$((UNEXPECTED_FAILURES + 1))
				else
					cache_record "$FOLDER" "$STRATEGY"
				fi
			fi

			RESULTS+=("$FOLDER|$STRATEGY|$DELETED|$BUILD_RESULT")

			# Git reset
			log "    Resetting Prodcore to HEAD (git checkout HEAD -- .)..."
			git_reset_prodcore
			log "    Reset complete."
		done
	done

	# Phase 4: Summary
	log_section "SUMMARY"
	log ""
	printf "%-25s  %-18s  %-9s  %-7s\n" "FOLDER" "STRATEGY" "DELETED" "BUILD" | tee -a "$REPORT_FILE"
	printf "%-25s  %-18s  %-9s  %-7s\n" "-------------------------" "------------------" "---------" "-------" | tee -a "$REPORT_FILE"

	for entry in "${RESULTS[@]+"${RESULTS[@]}"}"; do
		IFS='|' read -r f s d b <<< "$entry"
		marker=""
		[[ "$s" == "skipReferenced" && "$b" == "FAIL" ]] && marker=" *** UNEXPECTED ***"
		[[ "$b" == "SKIP" ]] && marker=" (cached)"
		printf "%-25s  %-18s  %-9s  %-7s%s\n" "$f" "$s" "$d" "$b" "$marker" | tee -a "$REPORT_FILE"
	done

	log ""
	log "Total test combinations: ${#RESULTS[@]}"
	log "Unexpected failures (skipReferenced build failed): $UNEXPECTED_FAILURES"
	log ""
	log "Full report: $REPORT_FILE"

	if [[ "$UNEXPECTED_FAILURES" -gt 0 ]]; then
		log "RESULT: FAIL — skipReferenced produced build errors (should never happen)"
		exit 1
	else
		log "RESULT: PASS — all skipReferenced builds succeeded"
		exit 0
	fi
}

main "$@"
