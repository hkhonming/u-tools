#!/bin/bash
# run-tests.sh - synthetic-repo tests for compare-ubuntu-kernel.sh categorizer.
# Pure bash + git + awk. Exit status non-zero on any failure.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$ROOT/compare-ubuntu-kernel.sh"
CONF="$ROOT/categories/linux-qcom.conf"
PASS=0
FAIL=0

fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL+1)); }
ok()   { PASS=$((PASS+1)); }
assert_eq() { # desc expected actual
    if [ "$2" = "$3" ]; then ok; else fail "$1: expected [$2] got [$3]"; fi
}

make_repo() { # $1 = dest dir
    local d="$1"
    git init -q -b master "$d"
    ( cd "$d"
      export GIT_AUTHOR_DATE="2026-01-01T00:00:00 +0000"
      export GIT_COMMITTER_DATE="2026-01-01T00:00:00 +0000"
      export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
      n=0
      c() { # subject [body]
          n=$((n+1)); echo "content $n" > "file$n"
          git add -A
          if [ -n "${2:-}" ]; then git commit -q -m "$1" -m "$2"
          else git commit -q -m "$1"; fi
      }
      c "initial commit"
      c "D: change to be duplicated"
      D_SHA=$(git rev-parse HEAD)
      c "UBUNTU: Ubuntu-7.0.0-38.38"
      BASE_SHA=$(git rev-parse HEAD)
      git branch -q upstream "$BASE_SHA"
      git checkout -q upstream
      c "U: upstream fix"
      U_SHA=$(git rev-parse HEAD)
      git checkout -q master
      c "UBUNTU: Ubuntu-qcom-7.0.0-1014.17"
      c "UBUNTU: [Config] enable foo"
      c "UBUNTU: [Packaging] update rules"
      c "UBUNTU: SAUCE: vendor hack"
      c "UBUNTU: [SAUCE] another vendor hack"
      c "UBUNTU: random note"
      c "FROMLIST: patch one"
      c "FROMLIST: patch two"
      c "FROMLOST: typo patch"          # aliased to FROMLIST:
      c "Revert \"FROMLIST: patch one\""
      c "FROMGIT: fromgit thing" "(cherry picked from commit deadbeefdeadbeefdeadbeefdeadbeefdeadbeef)"
      c "QCLINUX: qualcomm thing"
      c "PENDING: pending patch"
      c "PEDNING: typo pending patch"   # aliased to PENDING:
      c "WORKAROUND: workaround patch"
      c "untagged with verified ref" "(cherry picked from commit $U_SHA)"
      c "untagged dup of base" "(cherry picked from commit $D_SHA)"
      c "untagged with unknown ref" "(cherry picked from commit deadbeefdeadbeefdeadbeefdeadbeefdeadbeef)"
      c "PCI: foo"
      git checkout -q -b side HEAD~2
      c "side branch change"
      git checkout -q master
      git merge -q --no-ff side -m "Merge branch 'side'"
      echo "$BASE_SHA" > .test_base_sha
      echo "$D_SHA" > .test_d_sha
      echo "$U_SHA" > .test_u_sha )
}

csv_count() { # $1 csv output, $2 category -> commits
    printf '%s\n' "$1" | awk -F, -v cat="$2" '
        /^# Commits per category/ { insec = 1; next }
        insec && /^category,/ { next }
        insec && /^#/ { insec = 0 }
        insec && $1 == cat { print $2; exit }'
}

run_suite() { # $1 = awk binary
    local AWKBIN="$1"
    local T; T=$(mktemp -d) || exit 1
    make_repo "$T/repo"
    local BASE_SHA; BASE_SHA=$(cat "$T/repo/.test_base_sha")
    local OUT RC

    echo "== AWK=$AWKBIN"
    OUT=$(cd "$T/repo" && AWK="$AWKBIN" "$TOOL" -f csv --repo "$T/repo" -c \
        --category-config "$CONF" --upstream-ref upstream master 7.0 2>&1)
    RC=$?
    assert_eq "run ok ($AWKBIN)" 0 "$RC"

    # base detection ignores the qcom release commit
    assert_eq "base sha ($AWKBIN)" "$BASE_SHA" \
        "$(printf '%s\n' "$OUT" | grep -o "$BASE_SHA" | head -n 1)"
    assert_eq "FROMLIST count ($AWKBIN)" 3 "$(csv_count "$OUT" FROMLIST)"
    assert_eq "QCLINUX count ($AWKBIN)" 1 "$(csv_count "$OUT" QCLINUX)"
    assert_eq "PENDING count ($AWKBIN)" 2 "$(csv_count "$OUT" PENDING)"
    assert_eq "WORKAROUND count ($AWKBIN)" 1 "$(csv_count "$OUT" WORKAROUND)"
    assert_eq "Release count ($AWKBIN)" 1 "$(csv_count "$OUT" Release)"
    assert_eq "Config count ($AWKBIN)" 1 "$(csv_count "$OUT" Config)"
    assert_eq "Packaging count ($AWKBIN)" 1 "$(csv_count "$OUT" Packaging)"
    assert_eq "SAUCE count ($AWKBIN)" 2 "$(csv_count "$OUT" SAUCE)"
    assert_eq "Ubuntu other count ($AWKBIN)" 1 "$(csv_count "$OUT" "Ubuntu (other)")"
    assert_eq "FROMGIT count ($AWKBIN)" 1 "$(csv_count "$OUT" FROMGIT)"
    assert_eq "UPSTREAM verified ($AWKBIN)" 1 "$(csv_count "$OUT" "Upstream (verified)")"
    assert_eq "dup of base ($AWKBIN)" 1 "$(csv_count "$OUT" "Upstream (dup of base)")"
    assert_eq "unverified cherry-pick ($AWKBIN)" 1 "$(csv_count "$OUT" "Cherry-pick (unverified)")"
    # "PCI: foo" + "side branch change" are Uncategorized
    assert_eq "Uncategorized ($AWKBIN)" 2 "$(csv_count "$OUT" Uncategorized)"
    assert_eq "Revert count ($AWKBIN)" 1 "$(csv_count "$OUT" Revert)"
    assert_eq "Merge count ($AWKBIN)" 1 "$(csv_count "$OUT" Merge)"
    assert_eq "Total ($AWKBIN)" 21 "$(csv_count "$OUT" Total)"
    # ref not found sub row for FROMGIT (deadbeef ref)
    printf '%s\n' "$OUT" | grep -q "^  FROMGIT (ref not found)" \
        && ok || fail "FROMGIT ref-not-found sub row ($AWKBIN)"
    # revert sub row
    printf '%s\n' "$OUT" | grep -q "^  Revert (FROMLIST)" \
        && ok || fail "Revert (FROMLIST) sub row ($AWKBIN)"
    # alias line
    printf '%s\n' "$OUT" | grep -q "^# Aliased: FROMLOST: -> FROMLIST: (1)" \
        && ok || fail "alias line ($AWKBIN)"

    # --no-merges: merge commit excluded from total
    OUT=$(cd "$T/repo" && AWK="$AWKBIN" "$TOOL" -f csv --repo "$T/repo" -c \
        --category-config "$CONF" --upstream-ref upstream --no-merges master 7.0)
    assert_eq "no-merges total ($AWKBIN)" 20 "$(csv_count "$OUT" Total)"
    assert_eq "no-merges Merge row ($AWKBIN)" "" "$(csv_count "$OUT" Merge)"

    # default output unchanged without -c: no category section
    OUT=$(cd "$T/repo" && AWK="$AWKBIN" "$TOOL" -f csv --repo "$T/repo" master 7.0)
    printf '%s\n' "$OUT" | grep -q "Commits per category" \
        && fail "category section leaked without -c ($AWKBIN)" || ok

    # bad config -> exit 1 with config error
    echo "this is not a valid config line" > "$T/bad.conf"
    OUT=$(cd "$T/repo" && AWK="$AWKBIN" "$TOOL" -f csv --repo "$T/repo" -c \
        --category-config "$T/bad.conf" master 7.0 2>&1)
    RC=$?
    assert_eq "bad config rc ($AWKBIN)" 1 "$RC"
    printf '%s\n' "$OUT" | grep -q "config error line 1" \
        && ok || fail "bad config message ($AWKBIN): $OUT"

    # --list-commits adds per-commit table (text format)
    OUT=$(cd "$T/repo" && AWK="$AWKBIN" "$TOOL" -f text --repo "$T/repo" -c \
        --list-commits --category-config "$CONF" master 7.0)
    printf '%s\n' "$OUT" | grep -q "individual commits" \
        && ok || fail "--list-commits table ($AWKBIN)"

    rm -rf "$T"
}

for AWKBIN in awk mawk "busybox awk"; do
    if $AWKBIN 'BEGIN { print "ok" }' >/dev/null 2>&1; then
        run_suite "$AWKBIN"
    else
        echo "skip $AWKBIN (not installed)"
    fi
done

echo "passed=$PASS failed=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
