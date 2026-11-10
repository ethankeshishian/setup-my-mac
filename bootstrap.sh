#!/usr/bin/env bash
set -euo pipefail

dry_run=0
case "${1:-}" in
  --dry-run) dry_run=1; shift ;;
  '') ;;
  *) printf 'usage: bootstrap.sh [--dry-run]\n' >&2; exit 2 ;;
esac
[ "$#" -eq 0 ] || { printf 'usage: bootstrap.sh [--dry-run]\n' >&2; exit 2; }
[ "$(uname -m)" = arm64 ] || { printf 'smm requires arm64 macOS\n' >&2; exit 1; }
repo="$HOME/Repos/setup-my-mac"
if [ "$dry_run" -eq 1 ]; then
  printf '%s\n' \
    '1. Check arm64 architecture.' \
    '2. Install Nix with Determinate if missing.' \
    '3. Source the Nix profile.' \
    "4. If missing, clone https://github.com/ethankeshishian/setup-my-mac to $repo using nix run nixpkgs#git." \
    "5. exec nix run $repo#smm -- setup"
  exit 0
fi
# Recognize an existing installation before trying to install it again.
if ! command -v nix >/dev/null 2>&1 && [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  installer=$(mktemp)
  trap 'rm -f "$installer"' EXIT
  curl -fsSL https://install.determinate.systems/nix -o "$installer"
  sh "$installer" install
  rm -f "$installer"
  trap - EXIT
fi
for profile in /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh "$HOME/.nix-profile/etc/profile.d/nix.sh"; do
  if [ -f "$profile" ]; then
    # shellcheck source=/dev/null
    source "$profile"
    break
  fi
done
command -v nix >/dev/null 2>&1 || { printf 'Nix is unavailable; open a new shell and rerun bootstrap.sh\n' >&2; exit 1; }
if [ ! -d "$repo/.git" ]; then
  [ ! -e "$repo" ] || { printf 'Refusing to replace existing path: %s\n' "$repo" >&2; exit 1; }
  mkdir -p "$(dirname "$repo")"
  nix run nixpkgs#git -- clone https://github.com/ethankeshishian/setup-my-mac "$repo"
fi
exec nix run "$repo#smm" -- setup
