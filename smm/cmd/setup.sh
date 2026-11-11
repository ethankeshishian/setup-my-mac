#!/usr/bin/env bash

cmd_setup() (
  case "${1:-}" in
    --preview) [ "$#" -eq 1 ] || exit 2; smm_migrate_preview; exit "$?" ;;
    --plan)
      [ "$#" -le 2 ] || exit 2
      smm_setup_plan "${2:-$HOME/Desktop/smm-answers.json}"; exit "$?" ;;
    --answers)
      [ "$#" -eq 2 ] && [ -f "$2" ] || { warn 'usage: smm setup --answers <file>'; exit 2; }
      SMM_ANSWERS="$(cd -P "$(dirname "$2")" && pwd)/$(basename "$2")" || exit 1
      export SMM_ANSWERS
      jq -e 'type == "object"' "$SMM_ANSWERS" >/dev/null || { warn 'invalid answers file'; exit 1; } ;;
    '') ;;
    *) warn 'usage: smm setup [--preview | --plan [file] | --answers file]'; exit 2 ;;
  esac
  export SMM_SETUP_ORIGINAL_PATH="$PATH" SMM_AGENT_SETUP=1
  declare -p SETUP_STEPS >/dev/null 2>&1 || smm_setup_steps
  state=$(smm_state_dir) || exit 1
  smm_tx_begin setup || exit 1
  complete=0 paused=0 logger=''
  # shellcheck disable=SC2329
  smm_setup_cleanup() {
    local recovered=0
    # Exit 3 waits for an answer or a user action (SMM-NEEDS). Keep everything,
    # including an activated system, and resume from the same journal on rerun.
    if [ "$paused" -eq 1 ]; then touch "$SMM_TX/paused" || recovered=1
    elif [ "$complete" -eq 0 ]; then smm_setup_recover || recovered=1; fi
    if [ -n "$logger" ]; then
      # A signal can land while this shell still writes into the FIFO, so tee
      # would never see EOF. Let go of the FIFO, then wait briefly for tee.
      if { : >/dev/tty; } 2>/dev/null; then exec >/dev/tty 2>&1; else exec >/dev/null 2>&1; fi
      local tries=0
      while kill -0 "$logger" 2>/dev/null && [ "$tries" -lt 20 ]; do
        sleep 0.1; tries=$((tries + 1))
      done
      kill "$logger" 2>/dev/null || :
      wait "$logger" 2>/dev/null || :
    fi
    [ "$recovered" -ne 0 ] || [ "$paused" -eq 1 ] || rm -rf "$SMM_TX"
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
      if [ "$result" -eq 3 ]; then
        paused=1
        warn "setup paused at $step: ${reason:-waiting}. Changes so far are kept; provide it and run smm setup again to resume."
      else
        warn "setup stopped at $step: ${reason:-step failed}. Fix it and run smm setup again."
      fi
      exit "$result"
    fi
  done
  # Nothing is finalized until every step has succeeded.
  if [ -f "$state/setup-generation" ]; then smm_finalize_apply || exit 1; fi
  rm -f "$state/setup-generation"
  : > "$state/deduped"
  rm -f "$state/deduped-services" "$state/deduped-taps"
  complete=1
)
