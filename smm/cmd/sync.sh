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
  changes=$(git status --porcelain) || exit 1
  if [ -n "$changes" ]; then
    if ! smm_run_validate "$(smm_repo)"; then
      warn "fix ${SMM_FAILED_LINKS:-config} before syncing"; exit 1
    fi
    if [ "$supplied" -eq 0 ]; then
      printf 'Commit message: ' >&2
      IFS= read -r message || exit 1
    fi
    case "$message" in *[![:space:]]*) ;; *) warn 'empty commit message; sync aborted'; exit 1 ;; esac
    git add -A && git commit -m "$message" || exit 1
  fi
  smm_sync_merge_validated || exit 1
  smm_scan_outgoing origin/main..HEAD || exit 1
  gh auth status >/dev/null 2>&1 || { warn 'GitHub not signed in; push disabled'; exit 1; }
  git push origin HEAD:main || exit 1
  smm_run_apply
)
