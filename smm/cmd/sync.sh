#!/usr/bin/env bash

cmd_sync() (
  message='' supplied=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -m) [ "$#" -ge 2 ] || { warn 'usage: smm sync [-m message] [-y]'; exit 2; }; message=$2; supplied=1; shift 2 ;;
      -y) export SMM_YES=1; shift ;;
      *) warn 'usage: smm sync [-m message] [-y]'; exit 2 ;;
    esac
  done
  cd "$(smm_repo)" || exit 1
  # Reachability must be known before committing any local edits.
  git fetch origin || { warn "can't reach GitHub; nothing changed"; exit 1; }
  git rev-parse --verify origin/main >/dev/null || { warn 'origin/main is missing'; exit 1; }
  pre_sync=$(git rev-parse HEAD) || exit 1
  changes=$(git status --porcelain) || exit 1
  if [ -n "$changes" ]; then
    if ! smm_run_validate "$(smm_repo)"; then
      warn "fix ${SMM_FAILED_LINKS:-config} before syncing"; exit 1
    fi
    if [ "$supplied" -eq 0 ]; then
      printf 'Commit message: ' >&2
      IFS= read -r message </dev/tty || exit 1
    fi
    case "$message" in *[![:space:]]*) ;; *) warn 'empty commit message; sync aborted'; exit 1 ;; esac
    git add -A && git commit -m "$message" || exit 1
  fi
  # Preserve the user's own commit even if the incoming activation is rejected.
  git update-ref refs/smm/pre-sync HEAD || exit 1
  prev=$(smm_generation) || exit 1
  smm_tx_begin sync || exit 1
  switching=0 complete=0
  # shellcheck disable=SC2329
  smm_sync_restore() {
    local recovered=0
    if [ "$complete" -eq 0 ]; then
      if [ -f "$SMM_TX/merged" ]; then git reset --hard "$pre_sync" || recovered=1; fi
      if [ "$switching" -eq 1 ]; then smm_rollback "$prev" || recovered=1; fi
      smm_tx_restore || recovered=1
      if [ "$switching" -eq 1 ]; then
        smm_nvim_run '+Lazy! restore' || :
        smm_reload || :
      fi
    fi
    [ "$recovered" -ne 0 ] || rm -rf "$SMM_TX"
  }
  trap smm_sync_restore EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  state=$(smm_state_dir) || exit 1
  for file in applied.hash lazy-lock.hash lazy-lock.json last-build; do smm_tx_arm "$state/$file" || exit 1; done
  smm_tx_arm "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy" || exit 1
  smm_sync_merge_validated || exit 1
  smm_scan_outgoing origin/main..HEAD || exit 1
  gh auth status >/dev/null 2>&1 || { warn 'GitHub not signed in; push disabled'; exit 1; }
  switching=1
  smm_run_apply || exit 1
  git push origin HEAD:main || exit 1
  complete=1
)
