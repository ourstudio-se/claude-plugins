# Memory paths and frontmatter checks.

# tm_memory_path <path>: for a file in a team clone, prints "<team> <relative path>"; returns 1 outside the clones.
tm_memory_path() {
  local clones rel
  clones=$(tm_clones_dir)
  case "$1" in
    "$clones"/*/*) rel="${1#"$clones"/}" ;;
    *) return 1 ;;
  esac
  echo "${rel%%/*} ${rel#*/}"
}

# tm_valid_memory_rel <relative path>: general/<slug>.md or repos/<owner>/<repo>/<slug>.md.
tm_valid_memory_rel() {
  [[ "$1" =~ ^general/[a-z0-9][a-z0-9-]*\.md$ ]] || [[ "$1" =~ ^repos/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/[a-z0-9][a-z0-9-]*\.md$ ]]
}

# tm_frontmatter_problems <file>: one line per problem; nothing when the frontmatter is valid.
tm_frontmatter_problems() {
  local slug
  slug=$(basename "$1" .md)
  awk -v slug="$slug" '
    function value(line) { sub(/^[ \t]*[a-z_]+:[ \t]*/, "", line); if (line ~ /^".*"$/ || line ~ /^\047.*\047$/) line = substr(line, 2, length(line) - 2); return line }
    NR == 1 { if ($0 != "---") { print "the file must start with a --- frontmatter block"; bad = 1; exit } next }
    $0 == "---" { closed = 1; exit }
    /^[ \t]*name:/ { name = value($0) }
    /^[ \t]*description:/ { description = value($0) }
    /^[ \t]*type:/ { type = value($0) }
    /^[ \t]*author:/ { author = value($0) }
    /^[ \t]*date:/ { date = value($0) }
    END {
      if (bad) exit
      if (!closed) { print "the frontmatter block is not closed with ---"; exit }
      if (name != slug) print "name must be \"" slug "\", the file name without .md"
      if (description == "") print "description is missing"
      if (type !~ /^(project|reference|convention)$/) print "type must be project, reference or convention"
      if (author == "") print "author is missing"
      if (date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) print "date must be YYYY-MM-DD, the day the fact was last verified"
    }
  ' "$1"
}
