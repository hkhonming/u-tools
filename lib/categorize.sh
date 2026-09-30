#!/bin/bash
# categorize.sh - gather per-commit data for BASE..REF and categorize each
# commit using categorize.awk. Outputs one TSV line per commit:
#   sha<TAB>category<TAB>subcategory<TAB>insertions<TAB>deletions<TAB>subject<TAB>refsha<TAB>alias
#
# Usage: categorize.sh BASE REF [--config FILE] [--upstream-ref REF] [--no-merges]
set -u
AWK="${AWK:-awk}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

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
