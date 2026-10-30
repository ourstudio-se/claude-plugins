#!/usr/bin/env bash
# Clones or pulls one team's memory repo: sync.sh <team> <repo url>. Started in the background by the hooks.
set -u

team="$1"
repo="$2"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/settings.sh
. "$root/scripts/lib/settings.sh"

export GIT_TERMINAL_PROMPT=0
[ -n "${GIT_SSH_COMMAND:-}" ] || export GIT_SSH_COMMAND="ssh -o BatchMode=yes"

clone="$(tm_clones_dir)/$team"
state="$(tm_state_dir)/teams/$team"
mkdir -p "$state"

# One sync per team at a time; a lock older than 5 minutes is left over from a crash.
lock="$state/lock"
if ! mkdir "$lock" 2>/dev/null; then
  [ -n "$(find "$lock" -maxdepth 0 -mmin +5 2>/dev/null)" ] || exit 0
  rm -rf "$lock"
  mkdir "$lock" 2>/dev/null || exit 0
fi
trap 'rm -rf "$lock"' EXIT

# Notes are shown at the next session start.
note() {
  echo "$1" >>"$state/notes"
}

fresh_clone() {
  local tmp="$clone.tmp.$$"
  rm -rf "$tmp"
  git clone -q "$repo" "$tmp" 2>/dev/null || {
    rm -rf "$tmp"
    return 1
  }
  mkdir -p "$(dirname "$clone")"
  mv "$tmp" "$clone"
}

if [ ! -d "$clone/.git" ]; then
  fresh_clone || exit 1
  date +%s >"$state/last_pull"
  exit 0
fi

before=$(git -C "$clone" rev-parse -q --verify '@{u}' 2>/dev/null)
git -C "$clone" fetch -q origin 2>/dev/null || exit 1
after=$(git -C "$clone" rev-parse -q --verify '@{u}') || exit 1

if [ -n "$before" ] && ! git -C "$clone" merge-base --is-ancestor "$before" "$after"; then
  # The remote history was rewritten, e.g. to remove a leaked secret: start over from a fresh clone.
  unpushed=$(git -C "$clone" rev-list --count "$before..HEAD")
  old="$clone.old.$(date +%s)"
  mv "$clone" "$old"
  if ! fresh_clone; then
    mv "$old" "$clone"
    exit 1
  fi
  if [ "$unpushed" = "0" ]; then
    rm -rf "$old"
    note "The $team memory repo's history was rewritten, so the local clone was replaced with a fresh one."
  else
    note "The $team memory repo's history was rewritten. The clone was replaced; $unpushed unpushed commits are kept in $old."
  fi
elif ! git -C "$clone" merge -q --ff-only '@{u}' >/dev/null 2>&1; then
  if ! git -C "$clone" rebase -q '@{u}' >/dev/null 2>&1; then
    git -C "$clone" rebase --abort >/dev/null 2>&1
    note "Pulling the $team memory repo failed: local commits conflict with the remote."
  fi
fi

date +%s >"$state/last_pull"
