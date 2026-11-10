#!/usr/bin/env bash

cmd_setup() (
  case "${1:-}" in
    --preview) [ "$#" -eq 1 ] || exit 2; smm_migrate_preview; exit "$?" ;;
    '') ;;
    *) warn 'usage: smm setup [--preview]'; exit 2 ;;
  esac
  export SMM_SETUP_ORIGINAL_PATH="$PATH"
  declare -p SETUP_STEPS >/dev/null 2>&1 || smm_setup_steps
  state=$(smm_state_dir) || exit 1
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  trap 'smm_setup_recover; exit 130' INT
  trap 'smm_setup_recover; exit 143' TERM
  for step in "${SETUP_STEPS[@]}"; do
    if "step_${step}_done"; then continue; fi
    if "step_${step}_run" > "$tmp/output" 2>&1; then
      cat "$tmp/output"
      printf '%s done\n' "$step" >> "$state/setup.log"
    else
      cat "$tmp/output"
      reason=$(tail -n 1 "$tmp/output")
      smm_setup_recover || warn 'recovery incomplete; backups and dedupe journal retained'
      warn "setup stopped at $step: ${reason:-step failed}. Fix it and run smm setup again."
      exit 1
    fi
  done
)
