#!/bin/bash

usage() {
    echo "Usage: $0 [OPTIONS] <Ubuntu source tree> <git branch> <Ubuntu kernel version>"
    echo "       $0 [OPTIONS] --repo <path> <git ref> <Ubuntu kernel version>"
    echo "  <Ubuntu source tree>: A git/http URL to fetch target derivative kernel"
    echo "  <git branch>: E.g. master-next"
    echo "  <Ubuntu kernel version>: E.g. 5.15, 6.8"
    echo ""
    echo "Options:"
    echo "  -f, --format <format>    Output format: text (default), json, csv, markdown"
    echo "  -c, --categorize        Categorize commits on top of the base (see lib/categorize.awk)"
    echo "  --category-config FILE  Custom categorization config (see categories/*.conf)"
    echo "  --list-commits          With -c: also list each commit with its category"
    echo "  --repo PATH             Use an existing repository instead of cloning"
    echo "                          (positional args become <git ref> <version>)"
    echo "  --base-sha SHA           Use SHA as the base commit (skip auto-detection)"
    echo "  --base-tag TAG          Resolve TAG to a commit and use it as the base"
    echo "  --upstream-ref REF      Ref containing upstream commits (for verification)"
    echo "  --no-merges             Exclude merge commits from analysis"
    echo "  -h, --help              Show this help message"
    exit 1
}

# Default format
FORMAT="text"
CATEGORIZE=0
CATEGORY_CONFIG=""
LIST_COMMITS=0
REPO_PATH=""
BASE_SHA_OPT=""
BASE_TAG=""
UPSTREAM_REF=""
NO_MERGES=0
AWK="${AWK:-awk}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        -f|--format)
            FORMAT="$2"
            shift 2
            ;;
        -c|--categorize)
            CATEGORIZE=1
            shift
            ;;
        --category-config)
            CATEGORY_CONFIG="$2"
            shift 2
            ;;
        --list-commits)
            LIST_COMMITS=1
            shift
            ;;
        --repo)
            REPO_PATH="$2"
            shift 2
            ;;
        --base-sha)
            BASE_SHA_OPT="$2"
            shift 2
            ;;
        --base-tag)
            BASE_TAG="$2"
            shift 2
            ;;
        --upstream-ref)
            UPSTREAM_REF="$2"
            shift 2
            ;;
        --no-merges)
            NO_MERGES=1
            shift
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

# Check positional arguments
if [ -n "$REPO_PATH" ]; then
    if [ "$#" -ne 2 ]; then
        echo "Error: With --repo, this script requires exactly 2 positional arguments: <git ref> <version>." >&2
        usage
    fi
else
    if [ "$#" -ne 3 ]; then
        echo "Error: This script requires exactly 3 positional arguments." >&2
        usage
    fi
fi

# Resolve config to an absolute path before changing directory
if [ -n "$CATEGORY_CONFIG" ]; then
    if [ ! -f "$CATEGORY_CONFIG" ]; then
        echo "Error: --category-config file '$CATEGORY_CONFIG' not found." >&2
        exit 1
    fi
    CATEGORY_CONFIG=$(cd "$(dirname "$CATEGORY_CONFIG")" && pwd)/$(basename "$CATEGORY_CONFIG")
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

GIT_URL=""
REF=""
if [ -n "$REPO_PATH" ]; then
    REF="$1"
    BRANCH="$REF"
    VERSION="$2"
    if [ ! -d "$REPO_PATH/.git" ]; then
        echo "Error: --repo path '$REPO_PATH' is not a git repository." >&2
        exit 1
    fi
    cd "$REPO_PATH" || exit 1
else
    GIT_URL="$1"
    BRANCH="$2"
    VERSION="$3"
    REF="$BRANCH"
    rm -rf work_dir
    git clone -b "$BRANCH" --bare --filter=blob:none --single-branch "$GIT_URL" work_dir
    cd work_dir || exit 1
fi

# Determine the base commit (the Ubuntu release this derivative is built on)
if [ -n "$BASE_SHA_OPT" ]; then
    SHA=$(git rev-parse --verify "$BASE_SHA_OPT^{commit}" 2>/dev/null) || {
        echo "Error: Invalid --base-sha '$BASE_SHA_OPT'." >&2
        exit 1
    }
elif [ -n "$BASE_TAG" ]; then
    SHA=$(git rev-parse --verify "$BASE_TAG^{commit}" 2>/dev/null) || {
        echo "Error: Cannot resolve --base-tag '$BASE_TAG'." >&2
        exit 1
    }
else
    # First commit whose subject starts with "UBUNTU: Ubuntu-<VERSION>" literally
    # (a digit must follow "Ubuntu-", so "Ubuntu-qcom-..." is excluded).
    SHA=$(git log --format='%H %s' "$REF" | $AWK -v ver="$VERSION" '
        {
            msg = substr($0, 42)
            pre = "UBUNTU: Ubuntu-" ver
            if (index(msg, pre) == 1 && substr(msg, 16, 1) ~ /^[0-9]$/) {
                print $1
                exit
            }
        }')
    if [ -z "$SHA" ]; then
        echo "Error: No base commit found: no commit on '$REF' starts with 'UBUNTU: Ubuntu-$VERSION'." >&2
        exit 1
    fi
fi

# Collect data
COMMIT_COUNT=$(git rev-list --count "$SHA".."$BRANCH")
DIFF_STATS=$(git diff --shortstat "$SHA".."$BRANCH")

# Extract diff statistics
FILES_CHANGED=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ file' | grep -o '[0-9]\+' || echo "0")
INSERTIONS=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ insertion' | grep -o '[0-9]\+' || echo "0")
DELETIONS=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ deletion' | grep -o '[0-9]\+' || echo "0")

# Collect commits per kernel release
# Get all release commits with their SHAs and messages in chronological order
RELEASE_DATA=$(git log --reverse --grep="UBUNTU: Ubuntu-" --format="%H %s" "$SHA".."$BRANCH")

# Now count commits between consecutive releases
RELEASE_COMMITS=$(echo "$RELEASE_DATA" | awk -v base_sha="$SHA" '{
    # Extract commit SHA and message
    sha = $1
    msg = substr($0, index($0, $2))
    
    # Extract the release identifier from "UBUNTU: Ubuntu-<release>"
    release = ""
    if (match(msg, /UBUNTU: Ubuntu-[a-zA-Z0-9._-]+/)) {
        release = substr(msg, RSTART + 8, RLENGTH - 8)
    }
    
    if (release != "") {
        # Store each release SHA and name
        shas[NR] = sha
        releases[NR] = release
        count = NR
    }
}
END {
    # Count commits between base and first release, then between each consecutive release
    prev_sha = base_sha
    for (i = 1; i <= count; i++) {
        # Validate SHA format (40 hex characters) to prevent command injection
        # Silently skip invalid SHAs as they indicate data extraction issues
        if (prev_sha !~ /^[0-9a-f]{40}$/ || shas[i] !~ /^[0-9a-f]{40}$/) {
            continue
        }
        # Count commits from previous release to current release (inclusive of current)
        cmd = "git rev-list --count " prev_sha ".." shas[i]
        cmd | getline commit_count
        close(cmd)
        if (commit_count > 0) {
            printf "%s\t%d\n", releases[i], commit_count
        }
        prev_sha = shas[i]
    }
}' | tac)  # Reverse to show newest releases first (depends on git log --reverse at line 75)

# Collect per-folder statistics (top-level only)
FOLDER_STATS=$(git diff --numstat "$SHA".."$BRANCH" | awk 'BEGIN {FS="\t"} {
    if ($1 == "-" || $2 == "-") {
        # Binary file, count as 0 changes
        add = 0
        del = 0
    } else {
        add = +$1
        del = +$2
    }
    file = $3
    # Extract top-level directory
    split(file, parts, "/")
    if (length(parts) > 1) {
        dir = parts[1] "/"
    } else {
        dir = "(root)"
    }
    
    # Initialize if not already present
    if (!(dir in additions)) additions[dir] = 0
    if (!(dir in deletions)) deletions[dir] = 0
    
    files[dir]++
    additions[dir] += add
    deletions[dir] += del
}
END {
    for (dir in files) {
        printf "%s\t%d\t%d\t%d\n", dir, files[dir], additions[dir], deletions[dir]
    }
}' | sort -k2 -rn)

# Collect detailed per-folder statistics (2 levels, 4 for arch/)
FOLDER_STATS_DETAILED=$(git diff --numstat "$SHA".."$BRANCH" | awk 'BEGIN {FS="\t"} {
    if ($1 == "-" || $2 == "-") {
        # Binary file, count as 0 changes
        add = 0
        del = 0
    } else {
        add = +$1
        del = +$2
    }
    file = $3
    # Extract directory path based on depth rules
    split(file, parts, "/")
    if (length(parts) == 1) {
        dir = "(root)"
    } else {
        # For arch/, show up to 4 levels; otherwise 2 levels
        if (parts[1] == "arch") {
            depth = (length(parts) > 4) ? 4 : length(parts) - 1
        } else {
            depth = (length(parts) > 2) ? 2 : length(parts) - 1
        }
        
        dir = ""
        for (i = 1; i <= depth; i++) {
            dir = dir parts[i] "/"
        }
    }
    
    # Initialize if not already present
    if (!(dir in additions)) additions[dir] = 0
    if (!(dir in deletions)) deletions[dir] = 0
    
    files[dir]++
    additions[dir] += add
    deletions[dir] += del
}
END {
    for (dir in files) {
        printf "%s\t%d\t%d\t%d\n", dir, files[dir], additions[dir], deletions[dir]
    }
}' | sort -k2 -rn)

# Escape a string for embedding in JSON output (backslash, double quote)
json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
GIT_URL_JSON=$(json_escape "$GIT_URL")

# Categorize commits on top of the base (optional)
CATEGORY_TSV=""
if [ "$CATEGORIZE" -eq 1 ]; then
    if [ -n "$CATEGORY_CONFIG" ] && [ ! -f "$CATEGORY_CONFIG" ]; then
        echo "Error: --category-config file '$CATEGORY_CONFIG' not found." >&2
        exit 1
    fi
    . "$SCRIPT_DIR/lib/categorize.sh"
    categorize_run "$SHA" "$REF" || exit 1
    category_prepare
fi

# Output based on format
case $FORMAT in
    text)
        echo "### Base Ubuntu Commit ###"
        git log -1 "$SHA" | head -n 7
        echo ""
        echo "### Commits on top of generic Ubuntu ###"
        echo "$COMMIT_COUNT"
        echo "### Differences on top of generic Ubuntu ###"
        echo "$DIFF_STATS"
        echo ""
        echo "### Commits per kernel release ###"
        if [ -n "$RELEASE_COMMITS" ]; then
            printf "%-60s %10s\n" "Release" "Commits"
            # Generate separator: 60 (release col) + 1 (space) + 10 (commits col) + 1 (newline space) = 72
            printf '%*s\n' 71 | tr ' ' '-'
            echo "$RELEASE_COMMITS" | while IFS=$'\t' read -r release count; do
                printf "%-60s %10d\n" "$release" "$count"
            done
        else
            echo "No kernel release commits found."
        fi
        echo ""
        echo "### Per-folder breakdown ###"
        if [ -n "$FOLDER_STATS" ]; then
            printf "%-40s %10s %10s %10s\n" "Directory" "Files" "Insertions" "Deletions"
            printf "%-40s %10s %10s %10s\n" "----------------------------------------" "----------" "----------" "----------"
            echo "$FOLDER_STATS" | while IFS=$'\t' read -r dir files adds dels; do
                printf "%-40s %10d %10d %10d\n" "$dir" "$files" "$adds" "$dels"
            done
        else
            echo "No changes found."
        fi
        echo ""
        echo "### Detailed per-folder breakdown ###"
        if [ -n "$FOLDER_STATS_DETAILED" ]; then
            printf "%-50s %10s %10s %10s\n" "Directory" "Files" "Insertions" "Deletions"
            printf "%-50s %10s %10s %10s\n" "--------------------------------------------------" "----------" "----------" "----------"
            echo "$FOLDER_STATS_DETAILED" | while IFS=$'\t' read -r dir files adds dels; do
                printf "%-50s %10d %10d %10d\n" "$dir" "$files" "$adds" "$dels"
            done
        else
            echo "No changes found."
        fi
        if [ "$CATEGORIZE" -eq 1 ]; then
            echo ""
            category_render_text
            if [ "$LIST_COMMITS" -eq 1 ]; then
                echo ""
                category_render_commits
            fi
        fi
        ;;
    json)
        cat << EOF
{
  "git_url": "$GIT_URL_JSON",
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
  "commits_per_release": [
EOF
        
        # Build commits per release JSON array
        if [ -n "$RELEASE_COMMITS" ]; then
            echo "$RELEASE_COMMITS" | awk 'BEGIN {FS="\t"; first=1} {
                if (!first) printf ","
                first=0
                # Escape special characters for JSON
                release = $1
                gsub(/\\/, "\\\\", release)
                gsub(/"/, "\\\"", release)
                gsub(/\n/, "\\n", release)
                gsub(/\r/, "\\r", release)
                gsub(/\t/, "\\t", release)
                printf "\n    {\"release\": \"%s\", \"commits\": %d}", release, $2
            }
            END { printf "\n" }'
        fi
        
        cat << EOF
  ],
  "per_folder_stats": [
EOF
        
        # Build folder stats JSON array
        if [ -n "$FOLDER_STATS" ]; then
            echo "$FOLDER_STATS" | awk 'BEGIN {FS="\t"; first=1} {
                if (!first) printf ","
                first=0
                # Escape special characters in directory name for JSON
                dir = $1
                gsub(/\\/, "\\\\", dir)
                gsub(/"/, "\\\"", dir)
                gsub(/\n/, "\\n", dir)
                gsub(/\r/, "\\r", dir)
                gsub(/\t/, "\\t", dir)
                printf "\n    {\"directory\": \"%s\", \"files\": %d, \"insertions\": %d, \"deletions\": %d}", dir, $2, $3, $4
            }
            END { printf "\n" }'
        fi
        
        cat << EOF
  ],
  "per_folder_stats_detailed": [
EOF
        
        # Build detailed folder stats JSON array
        if [ -n "$FOLDER_STATS_DETAILED" ]; then
            echo "$FOLDER_STATS_DETAILED" | awk 'BEGIN {FS="\t"; first=1} {
                if (!first) printf ","
                first=0
                # Escape special characters in directory name for JSON
                dir = $1
                gsub(/\\/, "\\\\", dir)
                gsub(/"/, "\\\"", dir)
                gsub(/\n/, "\\n", dir)
                gsub(/\r/, "\\r", dir)
                gsub(/\t/, "\\t", dir)
                printf "\n    {\"directory\": \"%s\", \"files\": %d, \"insertions\": %d, \"deletions\": %d}", dir, $2, $3, $4
            }
            END { printf "\n" }'
        fi
        
        if [ "$CATEGORIZE" -eq 1 ]; then
            echo "  ],"
            category_render_json
            if [ "$LIST_COMMITS" -eq 1 ]; then
                echo ","
                category_render_commits_json
            fi
            echo "}"
        else
            cat << EOF
  ]
}
EOF
        fi
        ;;
    csv)
        if [ -n "$RELEASE_COMMITS" ]; then
            echo "# Commits per kernel release"
            echo "release,commits"
            echo "$RELEASE_COMMITS" | awk 'BEGIN {FS="\t"; OFS=","} {print $1, $2}'
            echo ""
        fi
        if [ -n "$FOLDER_STATS" ]; then
            echo "# Per-folder breakdown"
            echo "directory,files,insertions,deletions"
            echo "$FOLDER_STATS" | awk 'BEGIN {FS="\t"; OFS=","} {print $1, $2, $3, $4}'
            echo ""
        fi
        if [ -n "$FOLDER_STATS_DETAILED" ]; then
            echo "# Detailed per-folder breakdown"
            echo "directory,files,insertions,deletions"
            echo "$FOLDER_STATS_DETAILED" | awk 'BEGIN {FS="\t"; OFS=","} {print $1, $2, $3, $4}'
            echo ""
        fi
        echo "git_url,branch,base_version,base_commit_sha,commits_on_top,files_changed,insertions,deletions"
        echo "$GIT_URL,$BRANCH,$VERSION,$SHA,$COMMIT_COUNT,$FILES_CHANGED,$INSERTIONS,$DELETIONS"
        if [ "$CATEGORIZE" -eq 1 ]; then
            echo ""
            category_render_csv
        fi
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

### Commits per Kernel Release
EOF
        if [ -n "$RELEASE_COMMITS" ]; then
            echo ""
            echo "| Release | Commits |"
            echo "|---------|---------|"
            echo "$RELEASE_COMMITS" | while IFS=$'\t' read -r release count; do
                echo "| $release | $count |"
            done
        else
            echo ""
            echo "No kernel release commits found."
        fi
        
        cat << EOF

### Per-folder Breakdown
EOF
        if [ -n "$FOLDER_STATS" ]; then
            echo ""
            echo "| Directory | Files Changed | Insertions | Deletions |"
            echo "|-----------|---------------|------------|-----------|"
            echo "$FOLDER_STATS" | while IFS=$'\t' read -r dir files adds dels; do
                echo "| $dir | $files | $adds | $dels |"
            done
        else
            echo ""
            echo "No changes found."
        fi
        
        cat << EOF

### Detailed Per-folder Breakdown
EOF
        if [ -n "$FOLDER_STATS_DETAILED" ]; then
            echo ""
            echo "| Directory | Files Changed | Insertions | Deletions |"
            echo "|-----------|---------------|------------|-----------|"
            echo "$FOLDER_STATS_DETAILED" | while IFS=$'\t' read -r dir files adds dels; do
                echo "| $dir | $files | $adds | $dels |"
            done
        else
            echo ""
            echo "No changes found."
        fi
        if [ "$CATEGORIZE" -eq 1 ]; then
            category_render_markdown
        fi
        ;;
esac
