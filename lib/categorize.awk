# categorize.awk - first-match-wins commit categorizer (POSIX awk).
# Files (ARGV order): config, status map (sha<TAB>status), numstat
# (sha<TAB>ins<TAB>del), data (\037-separated: sha parents subject refsha body).
# Output per commit: sha<TAB>category<TAB>subcategory<TAB>ins<TAB>del<TAB>subject<TAB>refsha<TAB>alias

BEGIN { inherit_defaults = 1 }

function config_error(n) {
    printf "config error line %d\n", n > "/dev/stderr"
    bad = 1
    exit 1
}

# --- config file ------------------------------------------------------------
FILENAME == config_file {
    line = $0
    sub(/\r$/, "", line)
    if (line ~ /^#/ || line ~ /^$/) next
    n = split(line, p, "|")
    if (n == 2 && p[1] == "inherit_defaults" && p[2] ~ /^(yes|no)$/) {
        inherit_defaults = (p[2] == "yes") ? 1 : 0
        next
    }
    if (n == 3 && p[1] == "alias" && p[2] != "" && p[3] != "") {
        ana++
        a_from[ana] = p[2]
        a_to[ana] = p[3]
        next
    }
    if (n == 3 && (p[2] == "subject" || p[2] == "body")) {
        cna++
        c_name[cna] = p[1]
        c_type[cna] = p[2]
        c_re[cna] = p[3]
        next
    }
    config_error(FNR)
}

# --- status map / numstat ---------------------------------------------------
FILENAME == map_file { m_status[$1] = $2; next }
FILENAME == numstat_file { n_ins[$1] = $2; n_del[$1] = $3; next }

# --- data: one commit per line ----------------------------------------------
{
    split($0, f, "\037")
    sha = f[1]; par = f[2]; subj = f[3]; ref = f[4]; body = f[5]
    ins = (sha in n_ins) ? n_ins[sha] : 0
    del = (sha in n_del) ? n_del[sha] : 0

    # Apply aliases to the subject prefix (in config order), count each use
    subj2 = subj
    used = ""
    for (i = 1; i <= ana; i++) {
        if (index(subj2, a_from[i]) == 1) {
            subj2 = a_to[i] substr(subj2, length(a_from[i]) + 1)
            a_count[i]++
            if (used == "") used = a_from[i]
        }
    }

    subcat = ""
    if (par ~ / /) {
        cat = "Merge"                       # merge commit (multiple parents)
    } else if (index(subj2, "Revert \"") == 1) {
        cat = "Revert"
        inner = substr(subj2, 8)
        if (substr(inner, length(inner), 1) == "\"")
            inner = substr(inner, 1, length(inner) - 1)
        for (i = 1; i <= ana; i++) {
            if (index(inner, a_from[i]) == 1) {
                inner = a_to[i] substr(inner, length(a_from[i]) + 1)
                a_count[i]++
            }
        }
        subcat = cat_of(inner, body)
        if (subcat == "") subcat = "Uncategorized"
    } else {
        cat = cat_of(subj2, body)
        if (cat == "") {
            if (ref != "") {
                st = (ref in m_status) ? m_status[ref] : "unknown"
                if (st == "dup") cat = "Upstream (dup of base)"
                else if (st == "upstream") cat = "Upstream (verified)"
                else cat = "Cherry-pick (unverified)"
            } else {
                cat = "Uncategorized"
            }
        }
    }

    # For upstream-tagged commits, verify the referenced sha (if requested)
    if (upstream_ref != "" && (cat == "FROMGIT" || cat == "BACKPORT" || cat == "UPSTREAM")) {
        if (ref == "" || !(ref in m_status) || m_status[ref] != "upstream")
            subcat = "ref not found"
    }

    printf "%s\t%s\t%s\t%d\t%d\t%s\t%s\t%s\n", sha, cat, subcat, ins, del, subj, ref, used
}

# Category for a (alias-rewritten) subject, or "" if nothing matches.
function cat_of(s, b,    i) {
    for (i = 1; i <= cna; i++) {
        if (c_type[i] == "subject") { if (s ~ c_re[i]) return c_name[i] }
        else { if (b ~ c_re[i]) return c_name[i] }
    }
    if (inherit_defaults) return builtin_cat(s)
    return ""
}

function builtin_cat(s) {
    if (s ~ /^UBUNTU: Ubuntu-/) return "Release"
    if (s ~ /^UBUNTU: \[Config\]/) return "Config"
    if (s ~ /^UBUNTU: \[(Packaging|Debian)\]/) return "Packaging"
    if (s ~ /^UBUNTU: Start new release/) return "Packaging"
    if (s ~ /^UBUNTU: link-to-tracker/) return "Packaging"
    if (s ~ /^UBUNTU: SAUCE:/) return "SAUCE"
    if (s ~ /^UBUNTU: \[SAUCE\]/) return "SAUCE"
    if (s ~ /^UBUNTU: /) return "Ubuntu (other)"
    if (s ~ /^FROMLIST:/) return "FROMLIST"
    if (s ~ /^FROMGIT:/) return "FROMGIT"
    if (s ~ /^BACKPORT:/) return "BACKPORT"
    if (s ~ /^UPSTREAM:/) return "UPSTREAM"
    return ""
}

END {
    if (alias_file != "" && !bad) {
        for (i = 1; i <= ana; i++)
            if (a_count[i] > 0)
                printf "%s\t%s\t%d\n", a_from[i], a_to[i], a_count[i] > alias_file
    }
    if (bad) exit 1
}
