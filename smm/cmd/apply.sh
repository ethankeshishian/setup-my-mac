#!/usr/bin/env bash

cmd_apply() (
  case "${1:-}" in -y) export SMM_YES=1; shift ;; esac
  [ "$#" -eq 0 ] || { warn 'usage: smm apply [-y]'; exit 2; }
  state='' prev='' switching=0 complete=0 plugins=0 failed='' status=0 name='' errors='' built_hash=''
  original_path=$PATH
  passed=()
  state=$(smm_state_dir) || exit 1
  smm_tx_begin apply || exit 1
  # shellcheck disable=SC2329
  smm_apply_cleanup() {
    local recovery=0
    export PATH="$original_path"
    if [ "$complete" -eq 0 ]; then
      if [ "$switching" -eq 1 ]; then smm_rollback "$prev" || recovery=1; fi
      if [ "$plugins" -eq 1 ] && [ -f "$state/lazy-lock.json" ]; then
        # Temporarily load the previous pins, then put the user's edit back.
        if ! { cp "$(smm_repo)/config/nvim/lazy-lock.json" "$SMM_TX/edited-lock" &&
          cp "$state/lazy-lock.json" "$(smm_repo)/config/nvim/lazy-lock.json" &&
          smm_nvim_run '+Lazy! restore'; }; then warn 'previous plugin restore failed'; fi
        if [ -f "$SMM_TX/edited-lock" ]; then
          cp "$SMM_TX/edited-lock" "$(smm_repo)/config/nvim/lazy-lock.json" || recovery=1
        fi
      fi
      smm_tx_restore || recovery=1
      if [ "$switching" -eq 1 ]; then
        smm_setup_restore_brew || recovery=1
        [ "${#passed[@]}" -eq 0 ] || smm_reload "${passed[@]}" || :
      fi
    fi
    if [ "$recovery" -eq 0 ]; then rm -rf "$SMM_TX";
    else warn "recovery incomplete; journal retained: $SMM_TX"; fi
  }
  trap smm_apply_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  smm_tx_arm "$state/applied.hash" || exit 1
  if [ -f "$(smm_repo)/config/nvim/lazy-lock.json" ]; then
    lock_hash=$(shasum -a 256 "$(smm_repo)/config/nvim/lazy-lock.json" | awk '{print $1}') || exit 1
    if [ ! -f "$state/lazy-lock.hash" ] || [ "$lock_hash" != "$(cat "$state/lazy-lock.hash")" ]; then
      smm_tx_arm "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy" || exit 1
      plugins=1
      smm_nvim_run '+Lazy! restore' || exit 1
    fi
  fi
  # Keep validation in this shell so SMM_FAILED_LINKS survives.
  if ! smm_validate "$(smm_repo)" > "$SMM_TX/validation"; then
    status=1; failed=${SMM_FAILED_LINKS:-}
  fi
  errors=$(cat "$SMM_TX/validation")
  cat "$SMM_TX/validation"
  if [ "$status" -ne 0 ] && { [ -z "$failed" ] || smm_nix_changed; }; then
    warn 'validation failed; nothing activated'
    exit 1
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case " $failed " in *" $name "*) ;; *) passed+=("$name") ;; esac
  done < <(link_names)
  if smm_nix_changed; then
    prev=$(smm_generation) || { warn 'cannot determine previous generation'; exit 1; }
    built_hash=$(smm_nix_inputs_hash) || exit 1
    smm_build || { warn 'build failed; nothing activated'; exit 1; }
    smm_brew_resolve || exit 1
    if [ "$built_hash" != "$(smm_nix_inputs_hash)" ]; then
      smm_build || { warn 'build after adoption failed; nothing activated'; exit 1; }
    fi
    smm_use_build_tools || exit 1
    SMM_SKIP_AEROSPACE=1 smm_run_validate "$(smm_repo)" || exit 1
    switching=1
    smm_switch || { warn 'switch failed; rolling back'; exit 1; }
    smm_run_validate "$(smm_repo)" aerospace || exit 1
    if ! smm_health; then
      if [ "$(smm_health_reason aerospace)" = no-accessibility ]; then
        smm_wait_permission aerospace && smm_health || exit 1
      else exit 1; fi
    fi
    smm_reload borders || exit 1
  fi
  smm_secrets_materialize || exit 1
  [ "${#passed[@]}" -eq 0 ] || smm_reload "${passed[@]}" || status=1
  while IFS= read -r line; do
    case "$line" in 'fail '*) printf 'not reloaded %s\n' "${line#fail }" ;; esac
  done <<< "$errors"
  [ "$status" -eq 0 ] || exit "$status"
  if [ "$plugins" -eq 1 ]; then
    smm_tx_arm "$state/lazy-lock.hash" && smm_tx_arm "$state/lazy-lock.json" || exit 1
    cp "$(smm_repo)/config/nvim/lazy-lock.json" "$state/lazy-lock.json" || exit 1
    printf '%s\n' "$lock_hash" > "$state/lazy-lock.hash" || exit 1
  fi
  if [ "$switching" -eq 1 ]; then smm_finalize_apply || exit 1; fi
  complete=1
)
