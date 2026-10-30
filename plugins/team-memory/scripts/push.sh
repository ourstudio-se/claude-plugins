#!/usr/bin/env bash
# Pushes a team's memory commits: push.sh <team>. Retries after a rebase when someone else pushed first;
# on a real conflict, keeps the local version on a pending branch and resets main to the remote.
set -u

team="$1"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/settings.sh
. "$root/scripts/lib/settings.sh"

export GIT_TERMINAL_PROMPT=0
[ -n "${GIT_SSH_COMMAND:-}" ] || export GIT_SSH_COMMAND="ssh -o BatchMode=yes"

clone="$(tm_clones_dir)/$team"
state="$(tm_state_dir)/teams/$team"
[ -d "$clone/.git" ] || exit 0
mkdir -p "$state"

# Shares the lock with sync.sh; waits up to 30 s for a pull to finish.
lock="$state/lock"
tries=0
until mkdir "$lock" 2>/dev/null; do
  tries=$((tries + 1))
  [ "$tries" -lt 300 ] || exit 1
  sleep 0.1
done
trap 'rm -rf "$lock"' EXIT

note() {
  echo "$1" >>"$state/notes"
}

unpushed() {
  git -C "$clone" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0
}

[ "$(unpushed)" != "0" ] || exit 0

for _ in 1 2 3; do
  git -C "$clone" push -q origin HEAD 2>/dev/null && exit 0
  git -C "$clone" fetch -q origin 2>/dev/null || exit 1
  if ! git -C "$clone" rebase -q '@{u}' >/dev/null 2>&1; then
    git -C "$clone" rebase --abort >/dev/null 2>&1
    user=$(git -C "$clone" config user.email | cut -d @ -f 1 | tr -c 'A-Za-z0-9.-' '-' | sed 's/-*$//')
    branch="pending/${user:-local}/$(date +%Y%m%d-%H%M%S)"
    files=$(git -C "$clone" diff --name-only '@{u}...HEAD' | tr '\n' ' ')
    git -C "$clone" branch -q "$branch" HEAD
    git -C "$clone" reset -q --hard '@{u}'
    note "Conflict in ${files% }: someone else changed it while you edited. Your version is on the local branch $branch in $clone (git -C $clone show $branch:<file>); main now has theirs. Merge the two versions and save the memory again."
    exit 1
  fi
done
exit 1
