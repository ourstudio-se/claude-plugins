# Builds a team's memory index from frontmatter: one line per memory, never the bodies.

# tm_frontmatter <file>: prints "<date>\t<description>".
tm_frontmatter() {
  awk '
    NR == 1 && $0 != "---" { exit }
    NR > 1 && $0 == "---" { exit }
    /^[ \t]*description:/ { sub(/^[ \t]*description:[ \t]*/, ""); d = $0 }
    /^[ \t]*date:/ { sub(/^[ \t]*date:[ \t]*/, ""); t = $0 }
    function unquote(s) {
      if (s ~ /^".*"$/ || s ~ /^\047.*\047$/) return substr(s, 2, length(s) - 2)
      return s
    }
    END { print unquote(t) "\t" unquote(d) }
  ' "$1"
}

# tm_months_ago <n>: the date n months ago as YYYY-MM-DD (GNU or BSD date).
tm_months_ago() {
  date -d "-$1 months" +%Y-%m-%d 2>/dev/null || date -v-"$1"m +%Y-%m-%d
}

# tm_folder_entries <clone> <folder>: "<date>\t<path>\t<description>" per memory, newest first.
tm_folder_entries() {
  local f fm
  for f in "$1/$2"/*.md; do
    [ -f "$f" ] || continue
    fm=$(tm_frontmatter "$f")
    printf '%s\t%s\t%s\n' "${fm%%$'\t'*}" "$2/${f##*/}" "${fm#*$'\t'}"
  done | sort -r
}

# tm_format_entries <stale cutoff>: entries on stdin as index lines.
tm_format_entries() {
  awk -F '\t' -v cutoff="$1" '{
    line = "- " $2 ": " $3
    if ($1 == "") line = line " (no date)"
    else if ($1 < cutoff) line = line " (stale, verified " $1 ")"
    print line
  }'
}

tm_stale_cutoff() {
  tm_months_ago "$(jq -r .stale_after_months <<<"$1")"
}

# tm_capped_index <settings json> <team> <folder> <max>: index lines for a folder, newest first, at most max.
# When there are more, a last line starting with "#more " says so.
tm_capped_index() {
  local clone entries total
  clone="$(tm_clones_dir)/$2"
  entries=$(tm_folder_entries "$clone" "$3")
  [ -n "$entries" ] || return 0
  head -n "$4" <<<"$entries" | tm_format_entries "$(tm_stale_cutoff "$1")"
  total=$(wc -l <<<"$entries" | tr -d ' ')
  [ "$total" -le "$4" ] || echo "#more $((total - $4)) older memories in $3/ are not listed; search $clone/$3 when needed."
}

# tm_general_index <settings json> <team>: index lines for general/, at most max_general_index_lines.
tm_general_index() {
  tm_capped_index "$1" "$2" general "$(jq -r .max_general_index_lines <<<"$1")"
}

# tm_repo_index <settings json> <team> <repo key>: index lines for the repo's folder, at most max_repo_index_lines.
tm_repo_index() {
  tm_capped_index "$1" "$2" "$(tm_repo_folder "$3")" "$(jq -r .max_repo_index_lines <<<"$1")"
}
