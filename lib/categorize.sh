#!/bin/bash
# categorize.sh - gather per-commit data for BASE..REF and categorize each
# commit using categorize.awk. Outputs one TSV line per commit:
#   sha<TAB>category<TAB>subcategory<TAB>insertions<TAB>deletions<TAB>subject<TAB>refsha<TAB>alias
#
# Usage: categorize.sh BASE REF [--config FILE] [--upstream-ref REF] [--no-merges]
AWK="${AWK:-awk}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Sourceable helpers (used by compare-ubuntu-kernel.sh) ------------------

# categorize_run BASE REF
# Runs the categorizer pipeline; sets CATEGORY_TSV (per-commit TSV) and
# ALIAS_LINES ("from\tto\tcount" per applied alias). Returns non-zero on
# config errors.
categorize_run() {
    local base="$1" ref="$2" afile rc
    local args=("$SCRIPT_DIR/categorize.sh" "$base" "$ref")
    [ -n "${CATEGORY_CONFIG:-}" ] && args+=(--config "$CATEGORY_CONFIG")
    [ -n "${UPSTREAM_REF:-}" ] && args+=(--upstream-ref "$UPSTREAM_REF")
    [ "${NO_MERGES:-0}" -eq 1 ] && args+=(--no-merges)
    afile=$(mktemp) || return 1
    : > "$afile"
    CATEGORY_TSV=$(bash "${args[@]}" --alias-file "$afile")
    rc=$?
    if [ "$rc" -ne 0 ]; then
        rm -f "$afile"
        return "$rc"
    fi
    ALIAS_LINES=$(cat "$afile")
    rm -f "$afile"
    return 0
}

# category_summary_rows
# Aggregates CATEGORY_TSV into CATEGORY_SUMMARY: one line per row, in display
# order (categories by commit count desc, sub rows after their parent,
# Total last): "label\tcommits\tinsertions\tdeletions".
category_summary_rows() {
    CATEGORY_SUMMARY=$(printf '%s\n' "$CATEGORY_TSV" | $AWK 'BEGIN { FS = "\t" }
{
    cat = $2; subcat = $3; ins = $4; del = $5
    cnt[cat]++; ci[cat] += ins; cd[cat] += del
    total++; ti += ins; td += del
    if (subcat != "") scnt[cat "" subcat]++
}
END {
    nc = 0
    for (c in cnt) cats[++nc] = c
    for (i = 2; i <= nc; i++) {                 # sort by count desc
        cv = cats[i]; j = i - 1
        while (j >= 1 && cnt[cats[j]] < cnt[cv]) { cats[j+1] = cats[j]; j-- }
        cats[j+1] = cv
    }
    for (i = 1; i <= nc; i++) {
        c = cats[i]
        printf "%s\t%d\t%d\t%d\n", c, cnt[c], ci[c], cd[c]
        for (k in scnt) {
            if (index(k, c "") != 1) continue
            scat = substr(k, length(c) + 2)
            if (scat == "ref not found") label = "  " c " (ref not found)"
            else if (c == "Revert") label = "  Revert (" scat ")"
            else label = "  " c " (" scat ")"
            printf "%s\t%d\t\t\n", label, scnt[k]
        }
    }
    printf "TOTAL\t%d\t%d\t%d\n", total, ti, td
}')
}

# category_percent COMMITS -> percent of TOTAL_COMMITS, e.g. "42.3"
category_percent() {
    $AWK -v c="$1" -v t="$TOTAL_COMMITS" 'BEGIN { printf "%.1f", (t > 0) ? c * 100 / t : 0 }'
}

category_alias_lines() {
    if [ -n "$ALIAS_LINES" ]; then
        printf '%s\n' "$ALIAS_LINES" | while IFS="$(printf '\t')" read -r from to cnt; do
            echo "Aliased: $from -> $to ($cnt)"
        done
    fi
}

# category_render_text - "Commits per category" section (text format)
category_render_text() {
    echo "### Commits per category ###"
    printf "%-32s %8s %7s %12s %12s\n" "Category" "Commits" "%" "Insertions" "Deletions"
    printf "%-32s %8s %7s %12s %12s\n" "--------------------------------" "--------" "-------" "------------" "------------"
    printf '%s\n' "$CATEGORY_SUMMARY" | while IFS="$(printf '\t')" read -r label commits ins del; do
        if [ "$label" = "TOTAL" ]; then
            percent="100.0"; label="Total"
        else
            percent=$(category_percent "$commits")
        fi
        printf "%-32s %8s %7s %12s %12s\n" "$label" "$commits" "$percent" "${ins:--}" "${del:--}"
    done
    category_alias_lines
}

# category_render_csv
category_render_csv() {
    echo "# Commits per category"
    echo "category,commits,percent,insertions,deletions"
    printf '%s\n' "$CATEGORY_SUMMARY" | while IFS="$(printf '\t')" read -r label commits ins del; do
        if [ "$label" = "TOTAL" ]; then
            label="Total"; percent="100.0"
        else
            percent=$(category_percent "$commits")
        fi
        echo "$label,$commits,$percent,${ins:--},${del:--}"
    done
    echo ""
    if [ -n "$ALIAS_LINES" ]; then
        printf '%s\n' "$ALIAS_LINES" | while IFS="$(printf '\t')" read -r from to cnt; do
            echo "# Aliased: $from -> $to ($cnt)"
        done
    fi
}

# category_render_markdown
category_render_markdown() {
    echo ""
    echo "### Commits per Category"
    echo ""
    echo "| Category | Commits | % | Insertions | Deletions |"
    echo "|----------|---------|---|------------|-----------|"
    printf '%s\n' "$CATEGORY_SUMMARY" | while IFS="$(printf '\t')" read -r label commits ins del; do
        if [ "$label" = "TOTAL" ]; then
            label="Total"; percent="100.0"
        else
            percent=$(category_percent "$commits")
        fi
        echo "| $label | $commits | $percent | ${ins:--} | ${del:--} |"
    done
    if [ -n "$ALIAS_LINES" ]; then
        echo ""
        printf '%s\n' "$ALIAS_LINES" | while IFS="$(printf '\t')" read -r from to cnt; do
            echo "Aliased: $from -> $to ($cnt)"
        done
    fi
}

# category_prepare - build CATEGORY_SUMMARY and set TOTAL_COMMITS
category_prepare() {
    category_summary_rows
    TOTAL_COMMITS=$(printf '%s\n' "$CATEGORY_SUMMARY" | tail -n 1 | cut -f2)
}

# category_json_escape STRING - escape backslash and double quote
category_json_escape() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# category_render_json - prints "commits_per_category" and "aliases" JSON keys
# (no trailing comma; caller prints the closing brace)
category_render_json() {
    printf '%s\n' "$CATEGORY_TSV" | $AWK -v total_str="" 'BEGIN { FS = "\t"; first = 1 }
function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
{
    cat = $2; subcat = $3; ins = $4; del = $5
    cnt[cat]++; ci[cat] += ins; cd[cat] += del
    total++
    if (subcat != "") scnt[cat "\037" subcat]++
}
END {
    nc = 0
    for (c in cnt) cats[++nc] = c
    for (i = 2; i <= nc; i++) {
        cv = cats[i]; j = i - 1
        while (j >= 1 && cnt[cats[j]] < cnt[cv]) { cats[j+1] = cats[j]; j-- }
        cats[j+1] = cv
    }
    printf "  \"commits_per_category\": [\n"
    for (i = 1; i <= nc; i++) {
        c = cats[i]
        if (first) first = 0; else printf ",\n"
        pct = (total > 0) ? cnt[c] * 100 / total : 0
        printf "    {\"category\": \"%s\", \"commits\": %d, \"percent\": %.1f, \"insertions\": %d, \"deletions\": %d, \"subcategories\": [", esc(c), cnt[c], pct, ci[c], cd[c]
        sf = 1
        for (k in scnt) {
            if (index(k, c "\037") != 1) continue
            scat = substr(k, length(c) + 2)
            if (sf) sf = 0; else printf ", "
            printf "{\"subcategory\": \"%s\", \"commits\": %d}", esc(scat), scnt[k]
        }
        printf "]}"
    }
    printf "\n  ],\n"
    printf "  \"aliases\": ["
}
' 
    if [ -n "$ALIAS_LINES" ]; then
        printf '\n'
        printf '%s\n' "$ALIAS_LINES" | $AWK 'BEGIN { FS = "\t"; first = 1 }
function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
{
    if (first) first = 0; else printf ",\n"
    printf "    {\"from\": \"%s\", \"to\": \"%s\", \"count\": %d}", esc($1), esc($2), $3
}
END { printf "\n  ]" }'
    else
        printf ']'
    fi
    echo ""
}

# category_render_commits - per-commit table (short sha, category, subject)
category_render_commits() {
    echo "### Commits per category (individual commits) ###"
    printf "%-10s %-24s %s\n" "Sha" "Category" "Subject"
    printf "%-10s %-24s %s\n" "----------" "------------------------" "-------"
    printf '%s\n' "$CATEGORY_TSV" | while IFS="$(printf '\t')" read -r sha cat subcat ins del subj ref alias; do
        printf "%-10s %-24s %s\n" "${sha:0:8}" "$cat" "$subj"
    done
}

# category_render_commits_json - "commits" key (needs leading comma from caller)
category_render_commits_json() {
    echo "  \"commits\": ["
    printf '%s\n' "$CATEGORY_TSV" | $AWK 'BEGIN { FS = "\t"; first = 1 }
function esc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
{
    if (first) first = 0; else printf ",\n"
    printf "    {\"sha\": \"%s\", \"category\": \"%s\", \"subject\": \"%s\"}", substr($1, 1, 8), esc($2), esc($6)
}
END { printf "\n" }'
    echo "  ]"
}

if [ "${BASH_SOURCE[0]}" != "$0" ]; then return 0 2>/dev/null || true; fi

BASE=""
REF=""
CONFIG=""
UPSTREAM_REF=""
NO_MERGES=0
ALIAS_FILE=""
BASE_ARG="" ; REF_ARG=""
while [ $# -gt 0 ]; do
    case $1 in
        --config) CONFIG="$2"; shift 2 ;;
        --upstream-ref) UPSTREAM_REF="$2"; shift 2 ;;
        --no-merges) NO_MERGES=1; shift ;;
        --alias-file) ALIAS_FILE="$2"; shift 2 ;;
        *) if [ -z "$BASE_ARG" ]; then BASE_ARG="$1"; elif [ -z "$REF_ARG" ]; then REF_ARG="$1"; else echo "categorize.sh: extra arg $1" >&2; exit 1; fi; shift ;;
    esac
done
BASE="$BASE_ARG"; REF="$REF_ARG"
[ -n "$BASE" ] && [ -n "$REF" ] || { echo "categorize.sh: BASE and REF required" >&2; exit 1; }
[ -n "$CONFIG" ] || CONFIG="/dev/null"

# Field separator octal \x1f (037), record separator octal \x1e (036)
SEP=$(printf '\037')
RS_CH=$(printf '\036')
TMPDIR_C=$(mktemp -d) || exit 1
trap 'rm -rf "$TMPDIR_C"' EXIT

# --- Stream 1: sha, parents, subject, refsha (from cherry-pick/backport
# --- trailer line), body collapsed to one line -----------------------------
git log --format="%x1e%H%x1f%P%x1f%s%x1f%b" "$BASE..$REF" | $AWK -v RS="$RS_CH" -v no_merges="$NO_MERGES" '
{
    n = split($0, f, "\037")
    if (n < 3) next
    sha = f[1]; par = f[2]; subj = f[3]; body = (n >= 4) ? f[4] : ""
    if (par ~ / / && no_merges) next          # merge commit, excluded
    refsha = ""
    m = split(body, bl, "\n")
    for (i = 1; i <= m; i++) {
        if (bl[i] ~ /^\((cherry picked|backported) from commit [0-9a-f]+/) {
            if (match(bl[i], /commit [0-9a-f]+/))
                refsha = substr(bl[i], RSTART + 7, RLENGTH - 7)
        }
    }
    cbody = body
    gsub(/\n/, " ", cbody)
    gsub(/\036/, "", cbody); gsub(/\037/, " ", cbody)
    printf "%s\037%s\037%s\037%s\037%s\n", sha, par, subj, refsha, cbody
}' > "$TMPDIR_C/data"

# --- Stream 2: per-commit insertions/deletions ------------------------------
git log --numstat --format="%x1e%H" "$BASE..$REF" | $AWK -v RS="$RS_CH" '
{
    sub(/\036/, "")
    split($0, l, "\n")
    sha = l[1]
    ins = 0; del = 0
    for (i = 2; i in l; i++) {
        if (l[i] == "") continue
        split(l[i], nf, "\t")
        if (nf[1] == "-") a = 0; else a = +nf[1]
        if (nf[2] == "-") d = 0; else d = +nf[2]
        ins += a; del += d
    }
    printf "%s\t%d\t%d\n", sha, ins, del
}' > "$TMPDIR_C/numstat"

# --- Verify ref shas: batch existence check, then ancestry checks -----------
: > "$TMPDIR_C/map"
cut -d"$SEP" -f4 "$TMPDIR_C/data" | grep -v '^$' | sort -u > "$TMPDIR_C/refshas"
if [ -s "$TMPDIR_C/refshas" ]; then
    # Batch existence check (one git invocation for all shas)
    existing=$(git cat-file --batch-check='%(objectname) %(objecttype)'         < "$TMPDIR_C/refshas" 2>/dev/null | \
        $AWK '$2 == "commit" { print $1 }')
    for rsha in $existing; do
        if git merge-base --is-ancestor "$rsha" "$BASE" 2>/dev/null; then
            printf '%s\tdup\n' "$rsha" >> "$TMPDIR_C/map"
        elif [ -n "$UPSTREAM_REF" ] && git merge-base --is-ancestor "$rsha" "$UPSTREAM_REF" 2>/dev/null; then
            printf '%s\tupstream\n' "$rsha" >> "$TMPDIR_C/map"
        else
            printf '%s\tunknown\n' "$rsha" >> "$TMPDIR_C/map"
        fi
    done
fi

# --- Categorize -------------------------------------------------------------
ALIAS_TMP="$TMPDIR_C/aliases"
: > "$ALIAS_TMP"
$AWK -f "$SCRIPT_DIR/categorize.awk" \
    -v config_file="$CONFIG" -v map_file="$TMPDIR_C/map" \
    -v numstat_file="$TMPDIR_C/numstat" -v upstream_ref="$UPSTREAM_REF" \
    -v alias_file="$ALIAS_TMP" \
    "$CONFIG" "$TMPDIR_C/map" "$TMPDIR_C/numstat" "$TMPDIR_C/data"
rc=$?
if [ -n "$ALIAS_FILE" ] && [ -s "$ALIAS_TMP" ]; then
    cp "$ALIAS_TMP" "$ALIAS_FILE"
fi
exit $rc
