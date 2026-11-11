#!/usr/bin/env bash

# Each entry records the original path before a mutation is armed. Keeping the
# journal in state makes an interrupted recovery inspectable and retryable.
smm_tx_begin() {
  SMM_TX="$(smm_state_dir)/$1.transaction"
  # A run paused for an answer or user action resumes its own journal.
  if [ -f "$SMM_TX/paused" ]; then rm -f "$SMM_TX/paused" || return 1; export SMM_TX; return 0; fi
  mkdir "$SMM_TX" || { warn "recover existing transaction first: $SMM_TX"; return 1; }
  export SMM_TX
}
smm_tx_watch() {
  local path=$1 role=${2:-state} entry
  for entry in "$SMM_TX"/entry.*; do
    [ -f "$entry/path" ] || continue
    [ "$(cat "$entry/path")" != "$path" ] || return 0
  done
  entry=$(mktemp -d "$SMM_TX/entry.XXXXXX") || return 1
  printf '%s\n' "$path" > "$entry/path" || return 1
  printf '%s\n' "$role" > "$entry/role" || return 1
  if [ -e "$path" ] || [ -L "$path" ]; then
    cp -a "$path" "$entry/original" || return 1
  fi
  touch "$entry/ready"
}
smm_tx_arm() {
  local entry
  smm_tx_watch "$1" "${2:-state}" || return 1
  for entry in "$SMM_TX"/entry.*; do
    [ -f "$entry/ready" ] || continue
    [ "$(cat "$entry/path")" != "$1" ] || { touch "$entry/touched"; return; }
  done
  return 1
}
smm_tx_clear_targets() {
  local entry path
  for entry in "$SMM_TX"/entry.*; do
    [ -f "$entry/ready" ] || continue
    [ "$(cat "$entry/role")" = target ] || continue
    path=$(cat "$entry/path") || return 1
    # Arm even absent targets: activation may create them before failing.
    touch "$entry/touched" || return 1
    if [ ! -L "$path" ]; then rm -rf "${path:?}" || return 1; fi
  done
}
smm_tx_restore() {
  local entry path failed=0
  for entry in "$SMM_TX"/entry.*; do
    [ -f "$entry/touched" ] || continue
    path=$(cat "$entry/path") || { failed=1; continue; }
    rm -rf "${path:?}" || { failed=1; continue; }
    if [ -e "$entry/original" ] || [ -L "$entry/original" ]; then
      if ! { mkdir -p "$(dirname "$path")" && cp -a "$entry/original" "$path"; }; then failed=1; continue; fi
    fi
    rm -f "$entry/touched"
  done
  return "$failed"
}
smm_finalize_apply() {
  local state tmp
  state=$(smm_state_dir) || return 1
  tmp=$(mktemp "$state/applied.XXXXXX") || return 1
  smm_nix_inputs_hash > "$tmp" && mv "$tmp" "$state/applied.hash"
}
