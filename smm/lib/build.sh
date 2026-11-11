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
    for file in manifest/*.json manifest/prefs/*.json; do [ ! -f "$file" ] || printf '%s\n' "$file"; done
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
  ref=$(smm_flake_ref) || exit 1
  cd "$repo" || exit 1
  smm_rebuild build --flake "$ref#$host" || exit "$?"
  result=$(cd -P result && pwd) || exit 1
  printf '%s\n' "$result" > "$state/last-build" || exit 1
  printf '%s\n' "$ref" > "$state/last-build-flake"
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
    if [ -n "$generation" ]; then smm_sudo darwin-rebuild "$@"; return "$?"; fi
  fi
  smm_nix --sudo run "$(smm_repo)#darwin-rebuild" -- "$@"
}

smm_generation() {
  local generations profile=${SMM_SYSTEM_PROFILE:-/nix/var/nix/profiles/system} link
  # The profile link needs no lock; non-root --list-generations can fail with
  # "opening lock file .../system.lock: Permission denied" after first activation.
  if [ -L "$profile" ]; then
    link=$(readlink "$profile") || return 1
    case "$link" in
      system-*-link)
        link=${link#system-}; link=${link%-link}
        case "$link" in ''|*[!0-9]*) ;; *) printf '%s\n' "$link"; return 0 ;; esac ;;
    esac
  fi
  if ! generations=$(smm_rebuild --list-generations); then
    # A fresh Mac has no system profile yet.
    [ ! -e "$profile" ] && return 0
    return 1
  fi
  awk '/\(current\)/ && $1 ~ /^[0-9]+$/ { print $1; exit }' <<< "$generations"
}
smm_switch() {
  local repo host ref state
  repo=$(smm_repo) || return 1
  host=$(smm_host) || return 1
  ref=${SMM_FLAKE_REF:-$repo}
  if [ "${SMM_AGENT_SETUP:-0}" = 1 ]; then
    state=$(smm_state_dir) || return 1
    ref=$(cat "$state/last-build-flake") || return 1
  fi
  smm_rebuild_sudo switch --flake "$ref#$host" || return "$?"
  smm_prune_flake_snapshots
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

# Git flakes omit new generated modules. A path flake of the whole checkout
# would include ignored secrets, so snapshot only tracked/nonignored files.
smm_flake_ref() (
  set -o pipefail
  repo=$(smm_repo) || exit 1
  if [ "${SMM_AGENT_SETUP:-0}" != 1 ]; then printf '%s\n' "${SMM_FLAKE_REF:-$repo}"; exit 0; fi
  state=$(smm_state_dir) || exit 1
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  git -C "$repo" ls-files --cached --others --exclude-standard -z > "$tmp/files" || exit 1
  # Hash names, contents, symlink targets and executable bits, excluding ignored
  # secrets and deleted tracked files, exactly as they will appear in the copy.
  hash=$(
    while IFS= read -r -d '' file; do
      smm_safe_relative "$file" || exit 1
      if [ -L "$repo/$file" ]; then
        printf 'link %s\0' "$file"
        readlink "$repo/$file" || exit 1
      elif [ -f "$repo/$file" ]; then
        printf 'file %s\0' "$file"
        if [ -x "$repo/$file" ]; then printf 'executable\0'; else printf 'regular\0'; fi
        shasum -a 256 "$repo/$file" | awk '{print $1}' || exit 1
      fi
    done < "$tmp/files" | shasum -a 256 | awk '{print $1}'
  ) || exit 1
  for snapshot in "$state"/flake.*; do
    [ -f "$snapshot/hash" ] && [ -d "$snapshot/source" ] || continue
    if [ "$hash" = "$(cat "$snapshot/hash")" ]; then
      printf 'path:%s/source\n' "$snapshot"
      exit 0
    fi
  done
  snapshot=$(mktemp -d "$state/flake.XXXXXX") || exit 1
  # Clean incomplete snapshots on copy failure or interruption.
  trap 'rm -rf "$tmp"; [ -z "$snapshot" ] || rm -rf "$snapshot"' EXIT
  mkdir "$snapshot/source" || exit 1
  while IFS= read -r -d '' file; do
    smm_safe_relative "$file" || exit 1
    [ -f "$repo/$file" ] || [ -L "$repo/$file" ] || continue
    mkdir -p "$snapshot/source/$(dirname "$file")" || exit 1
    cp -a "$repo/$file" "$snapshot/source/$file" || exit 1
  done < "$tmp/files"
  printf '%s\n' "$hash" > "$snapshot/hash" || exit 1
  printf 'path:%s/source\n' "$snapshot"
  snapshot=''
)
smm_prune_flake_snapshots() {
  local state ref snapshot
  state=$(smm_state_dir) || return 1
  [ -f "$state/last-build-flake" ] || return 0
  ref=$(cat "$state/last-build-flake") || return 1
  # Only our snapshots are eligible. Keep the build reference for /etc evaluation
  # and retries, including when switching with a separate explicit flake ref.
  for snapshot in "$state"/flake.*; do
    [ -d "$snapshot" ] && [ ! -L "$snapshot" ] || continue
    [ "$ref" != "path:$snapshot/source" ] || continue
    rm -rf "$snapshot" || return 1
  done
}
