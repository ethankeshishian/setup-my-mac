#!/usr/bin/env bash

cmd_apply() {
  local validation failed='' name line prev built_hash errors='' status=0
  local passed=()
  case "${1:-}" in -y) export SMM_YES=1; shift ;; esac
  [ "$#" -eq 0 ] || { warn 'usage: smm apply [-y]'; return 2; }
  # Keep validation in this shell so SMM_FAILED_LINKS survives.
  validation=$(mktemp) || return 1
  if ! smm_validate "$(smm_repo)" > "$validation"; then
    status=1
    failed=${SMM_FAILED_LINKS:-}
  fi
  errors=$(cat "$validation")
  cat "$validation"
  rm -f "$validation"
  if [ "$status" -ne 0 ] && [ -z "$failed" ]; then
    warn 'validation could not read the manifest; nothing activated'
    return 1
  fi
  while IFS= read -r name; do
    case " $failed " in *" $name "*) ;; *) passed+=("$name") ;; esac
  done < <(link_names)
  if smm_nix_changed; then
    prev=$(smm_generation) || { warn 'cannot determine previous generation'; return 1; }
    built_hash=$(smm_nix_inputs_hash) || return 1
    smm_build || { warn 'build failed; nothing activated'; return 1; }
    smm_brew_resolve || return 1
    # Adoption changes the manifest. Activate a build containing those additions.
    if [ "$built_hash" != "$(smm_nix_inputs_hash)" ]; then
      smm_build || { warn 'build after adoption failed; nothing activated'; return 1; }
    fi
    if ! smm_switch; then
      warn 'switch failed; rolling back'
      smm_rollback "$prev" || warn 'rollback failed'
      [ "${#passed[@]}" -eq 0 ] || smm_reload "${passed[@]}" || :
      return 1
    fi
    if ! smm_health; then
      if [ "$(smm_health_reason aerospace)" = no-accessibility ]; then
        if declare -F smm_wait_permission >/dev/null; then
          smm_wait_permission aerospace || return 1
          if ! smm_health; then
            if [ "$(smm_health_reason aerospace)" != no-accessibility ]; then
              smm_rollback "$prev" || warn 'rollback failed'
              [ "${#passed[@]}" -eq 0 ] || smm_reload "${passed[@]}" || :
            fi
            return 1
          fi
        else
          warn 'Grant AeroSpace Accessibility in System Settings, then run smm apply again.'
          return 1
        fi
      else
        smm_rollback "$prev" || warn 'rollback failed'
        [ "${#passed[@]}" -eq 0 ] || smm_reload "${passed[@]}" || :
        return 1
      fi
    fi
    smm_reload borders || return 1
  fi
  smm_secrets_materialize || return 1
  [ "${#passed[@]}" -eq 0 ] || smm_reload "${passed[@]}" || status=1
  while IFS= read -r line; do
    case "$line" in 'fail '*) printf 'not reloaded %s\n' "${line#fail }" ;; esac
  done <<< "$errors"
  return "$status"
}
