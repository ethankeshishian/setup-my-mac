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
    '2. If Nix is missing, install the one this Mac uses (manifest/hosts.json: Lix or Determinate).' \
    '3. Source the Nix profile.' \
    "4. If missing, clone https://github.com/ethankeshishian/setup-my-mac to $repo using nix run nixpkgs#git." \
    "5. exec nix run $repo#smm -- setup"
  exit 0
fi
# Each Mac uses a fixed Nix implementation, recorded in manifest/hosts.json.
nix_impl() {
  local host impl
  host=$(scutil --get LocalHostName 2>/dev/null || true)
  impl=$(curl -fsSL https://raw.githubusercontent.com/ethankeshishian/setup-my-mac/main/manifest/hosts.json 2>/dev/null |
    /usr/bin/plutil -extract "$host.nix" raw -o - - 2>/dev/null || true)
  if [ -z "$impl" ]; then
    printf 'This Mac (%s) is new. Use Lix or Determinate Nix? [lix/determinate] ' "$host" >/dev/tty
    read -r impl </dev/tty
  fi
  case "$impl" in
    lix) printf '%s\n' https://install.lix.systems/lix ;;
    determinate|'') printf '%s\n' https://install.determinate.systems/nix ;;
    *) printf 'Unknown Nix implementation: %s\n' "$impl" >&2; return 1 ;;
  esac
}

# Recognize an existing installation before trying to install it again.
if ! command -v nix >/dev/null 2>&1 && [ ! -x /nix/var/nix/profiles/default/bin/nix ]; then
  url=$(nix_impl)
  installer=$(mktemp)
  trap 'rm -f "$installer"' EXIT
  curl -fsSL "$url" -o "$installer"
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
  nix --extra-experimental-features 'nix-command flakes' run nixpkgs#git -- clone https://github.com/ethankeshishian/setup-my-mac "$repo"
fi
exec nix --extra-experimental-features 'nix-command flakes' run "$repo#smm" -- setup </dev/tty
