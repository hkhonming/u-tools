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

# Extract diff statistics
FILES_CHANGED=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ file' | grep -o '[0-9]\+' || echo "0")
INSERTIONS=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ insertion' | grep -o '[0-9]\+' || echo "0")
DELETIONS=$(echo "$DIFF_STATS" | grep -o '[0-9]\+ deletion' | grep -o '[0-9]\+' || echo "0")

# Collect commits per kernel release
# First, get all release commits with their SHAs in reverse chronological order (newest first)
RELEASE_SHAS=$(git log --reverse --grep="UBUNTU: Ubuntu-" --format="%H %s" "$SHA".."$BRANCH")

# Now count commits between consecutive releases
RELEASE_COMMITS=$(echo "$RELEASE_SHAS" | awk -v base_sha="$SHA" '{
    # Extract commit SHA and message
    sha = $1
    msg = substr($0, index($0, $2))
    
    # Extract the release identifier from "UBUNTU: Ubuntu-<release>"
    release = ""
    if (match(msg, /UBUNTU: (Ubuntu-[a-zA-Z0-9._-]+)/, arr)) {
        release = arr[1]
    } else if (match(msg, /UBUNTU: Ubuntu-[a-zA-Z0-9._-]+/)) {
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
        # Count commits from previous release to current release (inclusive of current)
        cmd = "git rev-list --count " prev_sha ".." shas[i]
        cmd | getline commit_count
        close(cmd)
        if (commit_count > 0) {
            printf "%s\t%d\n", releases[i], commit_count
        }
        prev_sha = shas[i]
    }
}' | sort -t$'\t' -k2 -rn)

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
        ;;
    json)
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
        
        cat << EOF
  ]
}
EOF
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
        ;;
esac
