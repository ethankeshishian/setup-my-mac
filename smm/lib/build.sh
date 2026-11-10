#!/usr/bin/env bash

smm_host() { if [ -n "${SMM_HOST:-}" ]; then printf '%s\n' "$SMM_HOST"; else scutil --get LocalHostName; fi; }
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
  darwin-rebuild build --flake "$repo#$host" || exit "$?"
  result=$(cd -P result && pwd) || exit 1
  printf '%s\n' "$result" > "$state/last-build"
)
smm_generation() {
  local generations
  generations=$(darwin-rebuild --list-generations) || return 1
  awk '/\(current\)/ && $1 ~ /^[0-9]+$/ { print $1; found=1; exit } END { if (!found) exit 1 }' <<< "$generations"
}
smm_switch() {
  local repo host state hash
  repo=$(smm_repo) || return 1
  host=$(smm_host) || return 1
  state=$(smm_state_dir) || return 1
  hash=$(smm_nix_inputs_hash) || return 1
  sudo darwin-rebuild switch --flake "$repo#$host" || return "$?"
  printf '%s\n' "$hash" > "$state/applied.hash"
}
smm_rollback() {
  local state
  case "$1" in ''|*[!0-9]*) warn 'invalid generation'; return 2 ;; esac
  state=$(smm_state_dir) || return 1
  sudo darwin-rebuild switch --switch-generation "$1" || return "$?"
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
