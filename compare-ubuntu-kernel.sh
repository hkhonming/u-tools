#!/bin/bash

usage() {
    echo "Usage: $0 [OPTIONS] <Ubuntu source tree> <git branch> <Ubuntu kernel version>"
    echo "  <Ubuntu source tree>: A git/http URL to fetch target derivative kernel"
    echo "  <git branch>: E.g. master-next" 
    echo "  <Ubuntu kernel version>: E.g. 5.15, 6.8"
    echo ""
    echo "Options:"
    echo "  -f, --format <format>  Output format: text (default), json, csv, markdown"
    echo "  -h, --help             Show this help message"
    exit 1
}

# Default format
FORMAT="text"

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
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

# Check if exactly three positional arguments remain
if [ "$#" -ne 3 ]; then
    echo "Error: This script requires exactly 3 positional arguments." >&2
    usage
fi

# Validate format
case $FORMAT in
    text|json|csv|markdown)
        ;;
    *)
        echo "Error: Invalid format '$FORMAT'. Valid formats are: text, json, csv, markdown" >&2
        exit 1
        ;;
esac

GIT_URL="$1"
BRANCH="$2"
VERSION="$3"

git clone -b "$BRANCH" --bare --filter=blob:none --single-branch "$GIT_URL" work_dir
cd work_dir || exit 1

# Get commit SHA
SHA=$(git log --grep "UBUNTU: Ubuntu-$VERSION" | head -n 1 | cut -f 2 -d " ")

# Collect data
COMMIT_COUNT=$(git rev-list --count "$SHA".."$BRANCH")
DIFF_STATS=$(git diff --shortstat "$SHA".."$BRANCH")
FOLDER_STATS=$(git diff --dirstat "$SHA".."$BRANCH")

# Extract diff statistics
FILES_CHANGED=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ file' | grep -o '[0-9]\+' || echo "0")
INSERTIONS=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ insertion' | grep -o '[0-9]\+' || echo "0")
DELETIONS=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ deletion' | grep -o '[0-9]\+' || echo "0")

# Output based on format
case $FORMAT in
    text)
        echo "### Base Ubuntu Commit ###"
        git log --grep "UBUNTU: Ubuntu-$VERSION" | head -n 7
        echo ""
        echo "### Commits on top of generic Ubuntu ###"
        echo "$COMMIT_COUNT"
        echo "### Differences on top of generic Ubuntu ###"
        echo "$DIFF_STATS"
        echo ""
        echo "### Per-folder differences ###"
        if [ -n "$FOLDER_STATS" ]; then
            echo "$FOLDER_STATS"
        else
            echo "No folder differences"
        fi
        ;;
    json)
        # Convert folder stats to JSON array
        FOLDER_STATS_JSON="[]"
        if [ -n "$FOLDER_STATS" ]; then
            FOLDER_STATS_JSON=$(echo "$FOLDER_STATS" | awk '
                BEGIN { first=1; printf "[" }
                {
                    gsub(/%/, "", $1)
                    gsub(/\/$/, "", $2)
                    if (!first) printf ","
                    printf "{\"folder\": \"%s\", \"percentage\": %.1f}", $2, $1
                    first=0
                }
                END { printf "]" }
            ')
        fi
        
        cat << EOF
{
  "git_url": "$GIT_URL",
  "branch": "$BRANCH",
  "base_version": "$VERSION",
  "base_commit_sha": "$SHA",
  "commits_on_top": $COMMIT_COUNT,
  "diff_stats": {
    "files_changed": $FILES_CHANGED,
    "insertions": $INSERTIONS,
    "deletions": $DELETIONS,
    "raw": "$DIFF_STATS"
  },
  "folder_stats": $FOLDER_STATS_JSON
}
EOF
        ;;
    csv)
        # Convert folder stats to pipe-separated format
        FOLDER_STATS_CSV=""
        if [ -n "$FOLDER_STATS" ]; then
            FOLDER_STATS_CSV=$(echo "$FOLDER_STATS" | awk '{printf "%s:%s|", $1, $2}' | sed 's/|$//')
        fi
        
        echo "git_url,branch,base_version,base_commit_sha,commits_on_top,files_changed,insertions,deletions,folder_stats"
        echo "$GIT_URL,$BRANCH,$VERSION,$SHA,$COMMIT_COUNT,$FILES_CHANGED,$INSERTIONS,$DELETIONS,\"$FOLDER_STATS_CSV\""
        ;;
    markdown)
        cat << EOF
# Ubuntu Kernel Comparison Report

## Repository Information
- **Git URL**: $GIT_URL
- **Branch**: $BRANCH
- **Base Ubuntu Version**: $VERSION
- **Base Commit SHA**: \`$SHA\`

## Comparison Results

### Commits on Top of Generic Ubuntu
$COMMIT_COUNT commits

### Differences from Generic Ubuntu
| Metric | Count |
|--------|-------|
| Files Changed | $FILES_CHANGED |
| Insertions | $INSERTIONS |
| Deletions | $DELETIONS |

**Raw diff stats**: $DIFF_STATS

### Per-folder Differences
EOF
        
        if [ -n "$FOLDER_STATS" ]; then
            echo ""
            echo "| Folder | Percentage |"
            echo "|--------|------------|"
            echo "$FOLDER_STATS" | awk '{printf "| %s | %s |\n", $2, $1}'
        else
            echo ""
            echo "No folder differences"
        fi
        ;;
esac
