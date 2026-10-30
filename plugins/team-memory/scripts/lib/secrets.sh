# Secret scanning of memory text: built-in patterns, the team's extra patterns, and gitleaks when available.

# <rule name>|<grep flags>|<extended regex>
TM_SECRET_PATTERNS='aws-access-key|-E|(A3T[A-Z0-9]|AKIA|ASIA)[A-Z0-9]{16}
github-token|-E|gh[pousr]_[A-Za-z0-9]{36,}
github-fine-grained-token|-E|github_pat_[A-Za-z0-9_]{50,}
slack-token|-E|xox[abprs]-[A-Za-z0-9-]{10,}
private-key|-E|-----BEGIN[ A-Z]*PRIVATE KEY
anthropic-key|-E|sk-ant-[A-Za-z0-9_-]{20,}
openai-key|-E|sk-(proj-)?[A-Za-z0-9]{32,}
google-api-key|-E|AIza[0-9A-Za-z_-]{35}
stripe-key|-E|(sk|rk)_live_[0-9A-Za-z]{20,}
jwt|-E|eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}
azure-storage-key|-Ei|AccountKey=[A-Za-z0-9+/=]{40,}
shared-access-signature|-Ei|(SharedAccessKey|sig)=[A-Za-z0-9%+/=]{30,}
connection-string-password|-Ei|(password|pwd)=[^;[:space:]]{6,}
url-credentials|-Ei|[a-z][a-z0-9+.-]*://[^/[:space:]:@]+:[^/[:space:]@]{3,}@
secret-assignment|-Ei|(api[_-]?key|secret|token|passwd|password)["'\'']?[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9/+_=.-]{16,}'

tm_gitleaks_path() {
  if [ -n "${TEAM_MEMORY_GITLEAKS:-}" ]; then
    echo "$TEAM_MEMORY_GITLEAKS"
    return
  fi
  echo "$(tm_state_dir)/bin/gitleaks-$(head -n 1 "$(dirname "${BASH_SOURCE[0]}")/../gitleaks.sha256")"
}

tm_gitleaks_available() {
  [ -x "$(tm_gitleaks_path)" ]
}

# tm_scan_secrets <file> <team-memory.json or "">: prints the name of each rule that matches, never the match.
# Returns 1 when something was found.
tm_scan_secrets() {
  local file="$1" config="${2:-}" name flags regex found=""
  while IFS='|' read -r name flags regex; do
    grep -q "$flags" -- "$regex" "$file" && found="$found$name"$'\n'
  done <<<"$TM_SECRET_PATTERNS"
  if [ -n "$config" ] && [ -f "$config" ]; then
    while IFS=$'\t' read -r name regex; do
      [ -n "$regex" ] && grep -qE -- "$regex" "$file" && found="$found$name"$'\n'
    done < <(jq -r '.secret_patterns[]? | if type == "string" then ["team-pattern", .] else [.name // "team-pattern", .regex] end | @tsv' "$config" 2>/dev/null)
  fi
  if tm_gitleaks_available; then
    found="$found$(cd "$(dirname "$file")" && "$(tm_gitleaks_path)" stdin --no-banner -l error --redact \
      --report-format json --report-path /dev/stdout <"$file" 2>/dev/null | jq -r '.[]?.RuleID' 2>/dev/null)"
  fi
  found=$(printf '%s' "$found" | grep -v '^$' | sort -u)
  [ -z "$found" ] && return 0
  echo "$found"
  return 1
}
