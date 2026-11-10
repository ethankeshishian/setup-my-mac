#!/usr/bin/env bash

smm_host() { if [ -n "${SMM_HOST:-}" ]; then printf '%s\n' "$SMM_HOST"; else scutil --get LocalHostName; fi; }
# Hosts without a declaration retain the default until setup registers them.
smm_nix_impl() {
  local host impl
  host=$(smm_host) || return 1
  impl=$(jq -er --arg host "$host" '.[$host].nix // "determinate"' "$(smm_repo)/manifest/hosts.json") || return 1
  case "$impl" in
    determinate|lix) printf '%s\n' "$impl" ;;
    *) warn "invalid Nix implementation for $host: $impl"; return 1 ;;
  esac
}
smm_nix_inputs_hash() (
  set -o pipefail
  cd "$(smm_repo)" || exit 1
  {
    for file in flake.nix flake.lock; do [ ! -f "$file" ] || printf '%s\n' "$file"; done
    for dir in hosts modules smm; do
      [ ! -d "$dir" ] || find "$dir" -type f -print
    done
    for file in manifest/*.json; do [ ! -f "$file" ] || printf '%s\n' "$file"; done
  } | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file" || exit 1
  done | shasum -a 256 | awk '{print $1}'
)
smm_nix_changed() {
  local state hash
  state=$(smm_state_dir) || return 1
  hash=$(smm_nix_inputs_hash) || return 1
  [ ! -f "$state/applied.hash" ] || [ "$hash" != "$(cat "$state/applied.hash")" ]
}
smm_build() (
  repo=$(smm_repo) || exit 1
  host=$(smm_host) || exit 1
  state=$(smm_state_dir) || exit 1
  cd "$repo" || exit 1
  smm_rebuild build --flake "$repo#$host" || exit "$?"
  result=$(cd -P result && pwd) || exit 1
  printf '%s\n' "$result" > "$state/last-build"
)
# Bootstrap nix-darwin before its executable is installed by first activation.
smm_rebuild() {
  local generation
  if command -v darwin-rebuild >/dev/null 2>&1; then
    if [ "${1:-}" = --list-generations ]; then darwin-rebuild "$@"; return "$?"; fi
    generation=$(smm_generation) || return 1
    if [ -n "$generation" ]; then darwin-rebuild "$@"; return "$?"; fi
  fi
  smm_nix run "$(smm_repo)#darwin-rebuild" -- "$@"
}
smm_rebuild_sudo() {
  local generation
  if command -v darwin-rebuild >/dev/null 2>&1; then
    generation=$(smm_generation) || return 1
    if [ -n "$generation" ]; then sudo darwin-rebuild "$@"; return "$?"; fi
  fi
  smm_nix --sudo run "$(smm_repo)#darwin-rebuild" -- "$@"
}

smm_generation() {
  local generations
  if ! generations=$(smm_rebuild --list-generations); then
    # A fresh Mac has no system profile yet.
    [ ! -e /nix/var/nix/profiles/system ] && return 0
    return 1
  fi
  awk '/\(current\)/ && $1 ~ /^[0-9]+$/ { print $1; exit }' <<< "$generations"
}
smm_switch() {
  local repo host
  repo=$(smm_repo) || return 1
  host=$(smm_host) || return 1
  smm_rebuild_sudo switch --flake "$repo#$host"
}
smm_rollback() {
  local state
  # Empty means initial activation: callers restore files and deduped packages.
  [ -n "$1" ] || return 0
  case "$1" in *[!0-9]*) warn 'invalid generation'; return 2 ;; esac
  state=$(smm_state_dir) || return 1
  smm_rebuild_sudo switch --switch-generation "$1" || return "$?"
  rm -f "$state/applied.hash"
}

# Validators must use the candidate application's version before activation.
smm_use_build_tools() {
  local state result
  state=$(smm_state_dir) || return 1
  [ -f "$state/last-build" ] || return 0
  result=$(cat "$state/last-build") || return 1
  [ -d "$result/sw/bin" ] || { warn 'candidate build has no sw/bin'; return 1; }
  export PATH="$result/sw/bin:$PATH"
}
