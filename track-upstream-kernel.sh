#!/bin/bash

usage() {
    echo "Usage: $0 [OPTIONS] <kernel_repo> <from_tag> <to_tag>"
    echo "  <kernel_repo>: Git URL of the upstream Linux kernel repository"
    echo "  <from_tag>:    Base tag or commit (e.g. v6.14, v6.15-rc1)"
    echo "  <to_tag>:      Target RC tag or commit (e.g. v6.15-rc2)"
    echo ""
    echo "Options:"
    echo "  -c, --config <file>    JSON config file with folder/commit-message filters"
    echo "  -f, --format <format>  Output format: text (default), json, markdown"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Config file format:"
    echo '  {'
    echo '    "filters": ['
    echo '      { "name": "ARM64", "type": "folder", "paths": ["arch/arm64/"] },'
    echo '      { "name": "Security", "type": "commit_message", "patterns": ["CVE-"] }'
    echo '    ]'
    echo '  }'
    exit 1
}

# Defaults
FORMAT="text"
CONFIG_FILE=""

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        -*)
            echo "Error: Unknown option $1" >&2
            usage
            ;;
        *)
            break
            ;;
    esac
done

if [ "$#" -ne 3 ]; then
    echo "Error: This script requires exactly 3 positional arguments." >&2
    usage
fi

# Validate format
case $FORMAT in
    text|json|markdown)
        ;;
    *)
        echo "Error: Invalid format '$FORMAT'. Valid formats are: text, json, markdown" >&2
        exit 1
        ;;
esac

KERNEL_REPO="$1"
FROM_TAG="$2"
TO_TAG="$3"

# Validate tags contain only safe characters to prevent injection
if [[ ! "$FROM_TAG" =~ ^[a-zA-Z0-9._-]+$ ]] || [[ ! "$TO_TAG" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo "Error: Tags may only contain alphanumeric characters, '.', '_' and '-'." >&2
    exit 1
fi

# Clone upstream kernel (bare, no blobs for speed)
# Use a two-step init+fetch to pull only the two required tags
git init --bare upstream_work_dir >&2
git -C upstream_work_dir remote add origin "$KERNEL_REPO"
git -C upstream_work_dir fetch --filter=blob:none origin \
    "refs/tags/${FROM_TAG}:refs/tags/${FROM_TAG}" \
    "refs/tags/${TO_TAG}:refs/tags/${TO_TAG}" >&2

cd upstream_work_dir || exit 1

# ──────────────────────────────────────────────────────────────
# Helper: output a single filter result
# Arguments: name  type  result_summary  details_tsv
# ──────────────────────────────────────────────────────────────
print_filter_text() {
    local name="$1" type="$2" summary="$3" details="$4"
    echo "--- Filter: $name ($type) ---"
    echo "$summary"
    if [ -n "$details" ]; then
        echo "$details"
    fi
    echo ""
}

# ──────────────────────────────────────────────────────────────
# Collect overall stats
# ──────────────────────────────────────────────────────────────
TOTAL_COMMITS=$(git rev-list --count "${FROM_TAG}..${TO_TAG}" 2>/dev/null || echo 0)
DIFF_STATS=$(git diff --shortstat "${FROM_TAG}..${TO_TAG}" 2>/dev/null || echo "")
FILES_CHANGED=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ file' | grep -o '[0-9]\+' || echo "0")
INSERTIONS=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ insertion' | grep -o '[0-9]\+' || echo "0")
DELETIONS=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ deletion' | grep -o '[0-9]\+' || echo "0")

# ──────────────────────────────────────────────────────────────
# Process each filter from the config file (requires jq)
# ──────────────────────────────────────────────────────────────
FILTER_COUNT=0
if [ -n "$CONFIG_FILE" ] && [ -f "../$CONFIG_FILE" ]; then
    FILTER_COUNT=$(jq 'if .filters then (.filters | length) else 0 end' "../$CONFIG_FILE")
fi

# Collect filter results into parallel arrays (bash 3-compatible)
FILTER_NAMES=()
FILTER_TYPES=()
FILTER_SUMMARIES=()
FILTER_DETAILS=()

for idx in $(seq 0 $((FILTER_COUNT - 1))); do
    F_NAME=$(jq -r ".filters[$idx].name" "../$CONFIG_FILE")
    F_TYPE=$(jq -r ".filters[$idx].type" "../$CONFIG_FILE")

    case "$F_TYPE" in
        folder)
            # Build path args for git commands
            PATHS=$(jq -r ".filters[$idx].paths[]" "../$CONFIG_FILE" | tr '\n' '\0' | xargs -0 printf '%s\n')
            PATH_ARGS=()
            while IFS= read -r p; do PATH_ARGS+=("$p"); done <<< "$PATHS"

            FOLDER_COMMITS=$(git rev-list --count "${FROM_TAG}..${TO_TAG}" -- "${PATH_ARGS[@]}" 2>/dev/null || echo 0)
            FOLDER_DIFF=$(git diff --shortstat "${FROM_TAG}..${TO_TAG}" -- "${PATH_ARGS[@]}" 2>/dev/null || echo "")
            F_FILES=$(echo "$FOLDER_DIFF" | grep -o '[0-9]\+ file' | grep -o '[0-9]\+' || echo "0")
            F_INS=$(echo "$FOLDER_DIFF" | grep -o '[0-9]\+ insertion' | grep -o '[0-9]\+' || echo "0")
            F_DEL=$(echo "$FOLDER_DIFF" | grep -o '[0-9]\+ deletion' | grep -o '[0-9]\+' || echo "0")

            SUMMARY="commits=$FOLDER_COMMITS files_changed=$F_FILES insertions=$F_INS deletions=$F_DEL"

            # Per-path numstat details
            DETAILS=$(git diff --numstat "${FROM_TAG}..${TO_TAG}" -- "${PATH_ARGS[@]}" 2>/dev/null | \
                awk 'BEGIN{FS="\t"} {
                    add = ($1=="-") ? 0 : +$1
                    del = ($2=="-") ? 0 : +$2
                    printf "%s\t%d\t%d\n", $3, add, del
                }')

            FILTER_NAMES+=("$F_NAME")
            FILTER_TYPES+=("folder")
            FILTER_SUMMARIES+=("$SUMMARY")
            FILTER_DETAILS+=("$DETAILS")
            ;;

        commit_message)
            PATTERNS=$(jq -r ".filters[$idx].patterns[]" "../$CONFIG_FILE")

            # Build grep args (one --grep per pattern)
            GREP_ARGS=()
            while IFS= read -r pat; do GREP_ARGS+=(--grep="$pat"); done <<< "$PATTERNS"

            MATCHED_COMMITS=$(git log --oneline "${GREP_ARGS[@]}" "${FROM_TAG}..${TO_TAG}" 2>/dev/null || echo "")
            MATCH_COUNT=$(echo "$MATCHED_COMMITS" | grep -c . || echo 0)
            [ -z "$MATCHED_COMMITS" ] && MATCH_COUNT=0

            SUMMARY="matched_commits=$MATCH_COUNT"
            DETAILS="$MATCHED_COMMITS"

            FILTER_NAMES+=("$F_NAME")
            FILTER_TYPES+=("commit_message")
            FILTER_SUMMARIES+=("$SUMMARY")
            FILTER_DETAILS+=("$DETAILS")
            ;;

        *)
            echo "Warning: unknown filter type '$F_TYPE' for filter '$F_NAME', skipping." >&2
            ;;
    esac
done

# ──────────────────────────────────────────────────────────────
# Output
# ──────────────────────────────────────────────────────────────
GENERATION_DATE=$(date -u '+%Y-%m-%d %H:%M:%S UTC')

case $FORMAT in
    text)
        echo "### Upstream Linux Kernel RC Tracker ###"
        echo "From : $FROM_TAG"
        echo "To   : $TO_TAG"
        echo "Date : $GENERATION_DATE"
        echo ""
        echo "### Overall Changes ###"
        echo "Total commits : $TOTAL_COMMITS"
        echo "Files changed : $FILES_CHANGED"
        echo "Insertions    : $INSERTIONS"
        echo "Deletions     : $DELETIONS"
        echo ""

        if [ "${#FILTER_NAMES[@]}" -gt 0 ]; then
            echo "### Filter Results ###"
            for i in "${!FILTER_NAMES[@]}"; do
                print_filter_text "${FILTER_NAMES[$i]}" "${FILTER_TYPES[$i]}" "${FILTER_SUMMARIES[$i]}" "${FILTER_DETAILS[$i]}"
            done
        fi
        ;;

    json)
        # Build filters JSON array using jq for safe string encoding
        FILTERS_JSON="["
        FIRST=1
        for i in "${!FILTER_NAMES[@]}"; do
            [ "$FIRST" -eq 0 ] && FILTERS_JSON+=","
            FIRST=0
            F_NAME_ESC=$(jq -Rn --arg v "${FILTER_NAMES[$i]}" '$v')
            F_TYPE_ESC=$(jq -Rn --arg v "${FILTER_TYPES[$i]}" '$v')
            SUMMARY="${FILTER_SUMMARIES[$i]}"
            DETAILS="${FILTER_DETAILS[$i]}"

            if [ "${FILTER_TYPES[$i]}" = "folder" ]; then
                F_COMMITS=$(echo "$SUMMARY" | grep -o 'commits=[0-9]*' | cut -d= -f2)
                F_FILES=$(echo "$SUMMARY" | grep -o 'files_changed=[0-9]*' | cut -d= -f2)
                F_INS=$(echo "$SUMMARY" | grep -o 'insertions=[0-9]*' | cut -d= -f2)
                F_DEL=$(echo "$SUMMARY" | grep -o 'deletions=[0-9]*' | cut -d= -f2)
                FILTERS_JSON+="{\"name\":$F_NAME_ESC,\"type\":$F_TYPE_ESC,\"commits\":$F_COMMITS,\"files_changed\":$F_FILES,\"insertions\":$F_INS,\"deletions\":$F_DEL}"
            else
                MATCH_COUNT=$(echo "$SUMMARY" | grep -o 'matched_commits=[0-9]*' | cut -d= -f2)
                # Build JSON array of matched commit lines using jq for safe encoding
                COMMIT_LIST_JSON=$(echo "$DETAILS" | grep -v '^$' | jq -Rn '[inputs]')
                FILTERS_JSON+="{\"name\":$F_NAME_ESC,\"type\":$F_TYPE_ESC,\"matched_commits\":$MATCH_COUNT,\"commits\":$COMMIT_LIST_JSON}"
            fi
        done
        FILTERS_JSON+="]"

        cat << EOF
{
  "kernel_repo": "$KERNEL_REPO",
  "from_tag": "$FROM_TAG",
  "to_tag": "$TO_TAG",
  "generated_at": "$GENERATION_DATE",
  "overall": {
    "total_commits": $TOTAL_COMMITS,
    "files_changed": $FILES_CHANGED,
    "insertions": $INSERTIONS,
    "deletions": $DELETIONS
  },
  "filters": $FILTERS_JSON
}
EOF
        ;;

    markdown)
        cat << EOF
# Upstream Linux Kernel RC Tracker

## Release Comparison

| Property | Value |
|----------|-------|
| From | \`$FROM_TAG\` |
| To | \`$TO_TAG\` |
| Generated | $GENERATION_DATE |

## Overall Changes

| Metric | Count |
|--------|-------|
| Total Commits | $TOTAL_COMMITS |
| Files Changed | $FILES_CHANGED |
| Insertions | $INSERTIONS |
| Deletions | $DELETIONS |

EOF

        if [ "${#FILTER_NAMES[@]}" -gt 0 ]; then
            echo "## Filter Results"
            echo ""
            for i in "${!FILTER_NAMES[@]}"; do
                echo "### ${FILTER_NAMES[$i]} (${FILTER_TYPES[$i]})"
                echo ""
                if [ "${FILTER_TYPES[$i]}" = "folder" ]; then
                    SUMMARY="${FILTER_SUMMARIES[$i]}"
                    F_COMMITS=$(echo "$SUMMARY" | grep -o 'commits=[0-9]*' | cut -d= -f2)
                    F_FILES=$(echo "$SUMMARY" | grep -o 'files_changed=[0-9]*' | cut -d= -f2)
                    F_INS=$(echo "$SUMMARY" | grep -o 'insertions=[0-9]*' | cut -d= -f2)
                    F_DEL=$(echo "$SUMMARY" | grep -o 'deletions=[0-9]*' | cut -d= -f2)
                    echo "| Metric | Count |"
                    echo "|--------|-------|"
                    echo "| Commits | $F_COMMITS |"
                    echo "| Files Changed | $F_FILES |"
                    echo "| Insertions | $F_INS |"
                    echo "| Deletions | $F_DEL |"
                    echo ""
                    DETAILS="${FILTER_DETAILS[$i]}"
                    if [ -n "$DETAILS" ]; then
                        echo "#### Changed Files"
                        echo ""
                        echo "| File | Insertions | Deletions |"
                        echo "|------|-----------|-----------|"
                        echo "$DETAILS" | while IFS=$'\t' read -r file ins del; do
                            echo "| $file | $ins | $del |"
                        done
                        echo ""
                    fi
                else
                    MATCH_COUNT=$(echo "${FILTER_SUMMARIES[$i]}" | grep -o 'matched_commits=[0-9]*' | cut -d= -f2)
                    echo "**Matched commits:** $MATCH_COUNT"
                    echo ""
                    DETAILS="${FILTER_DETAILS[$i]}"
                    if [ -n "$DETAILS" ]; then
                        echo "#### Matching Commits"
                        echo ""
                        echo "\`\`\`"
                        echo "$DETAILS"
                        echo "\`\`\`"
                        echo ""
                    fi
                fi
            done
        fi
        ;;
esac
