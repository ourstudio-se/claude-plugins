#!/usr/bin/env bash
# Downloads the pinned gitleaks release once and verifies its checksum. Started in the background at session start.
set -u

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/settings.sh
. "$root/scripts/lib/settings.sh"
# shellcheck source=lib/secrets.sh
. "$root/scripts/lib/secrets.sh"

pins="$root/scripts/gitleaks.sha256"
version=$(head -n 1 "$pins")
target=$(tm_gitleaks_path)
[ -x "$target" ] && exit 0

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) exit 1 ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=x64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) exit 1 ;;
esac
asset="gitleaks_${version}_${os}_${arch}.tar.gz"
expected=$(awk -v a="$asset" '$2 == a { print $1 }' "$pins")
[ -n "$expected" ] || exit 1

dir=$(dirname "$target")
mkdir -p "$dir"
lock="$dir/download.lock"
mkdir "$lock" 2>/dev/null || exit 0
tmp=$(mktemp -d "$dir/download.XXXXXX")
trap 'rm -rf "$lock" "$tmp"' EXIT

curl -fsSL --max-time 120 -o "$tmp/$asset" "https://github.com/gitleaks/gitleaks/releases/download/v$version/$asset" || exit 1
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$tmp/$asset" | cut -d ' ' -f 1)
else
  actual=$(shasum -a 256 "$tmp/$asset" | cut -d ' ' -f 1)
fi
[ "$actual" = "$expected" ] || exit 1
tar -xzf "$tmp/$asset" -C "$tmp" gitleaks || exit 1
chmod +x "$tmp/gitleaks"
mv "$tmp/gitleaks" "$target"
