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
  smm_tx_begin setup || exit 1
  complete=0 logger=''
  # shellcheck disable=SC2329
  smm_setup_cleanup() {
    local recovered=0
    if [ "$complete" -eq 0 ]; then smm_setup_recover || recovered=1; fi
    if [ -n "$logger" ]; then wait "$logger" || :; fi
    [ "$recovered" -ne 0 ] || rm -rf "$SMM_TX"
  }
  trap smm_setup_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  smm_tx_arm "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy" || exit 1
  for step in "${SETUP_STEPS[@]}"; do
    if "step_${step}_done"; then continue; fi
    # A FIFO streams output through tee without running the step in a pipeline
    # subshell (host selection and candidate PATH must survive between steps).
    mkfifo "$SMM_TX/output" || exit 1
    tee -a "$state/setup.log" < "$SMM_TX/output" &
    logger=$!
    result=0
    "step_${step}_run" > "$SMM_TX/output" 2>&1 || result=$?
    wait "$logger" || result=1
    logger=''
    rm "$SMM_TX/output" || exit 1
    if [ "$result" -eq 0 ]; then
      printf '%s done\n' "$step" >> "$state/setup.log"
    else
      reason=$(tail -n 1 "$state/setup.log")
      warn "setup stopped at $step: ${reason:-step failed}. Fix it and run smm setup again."
      exit 1
    fi
  done
  # Nothing is finalized until every step has succeeded.
  if [ -f "$state/setup-generation" ]; then smm_finalize_apply || exit 1; fi
  rm -f "$state/setup-generation"
  : > "$state/deduped"
  complete=1
)
