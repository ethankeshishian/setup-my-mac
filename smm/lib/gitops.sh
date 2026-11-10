#!/usr/bin/env bash

smm_sync_merge_validated() (
  repo=$(smm_repo) || exit 1
  state=$(smm_state_dir) || exit 1
  wt="$state/sync-wt"
  mkdir "$state/sync.lock" 2>/dev/null || { warn 'sync already in progress'; exit 1; }
  added=0
  # Called by EXIT, including interrupted and failed merges.
  # shellcheck disable=SC2329
  smm_sync_cleanup() {
    if [ "$added" -eq 1 ] && [ -e "$wt/.git" ]; then
      git -C "$repo" worktree remove --force "$wt" || warn "could not remove sync worktree: $wt"
    fi
    rmdir "$state/sync.lock" 2>/dev/null || :
  }
  trap smm_sync_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  [ ! -e "$wt" ] || { warn "sync worktree already exists: $wt"; exit 1; }
  # Register cleanup before git returns: a signal can arrive just after creation.
  added=1
  git -C "$repo" worktree add --detach "$wt" HEAD || exit 1
  if ! git -C "$wt" merge --no-edit origin/main; then
    conflicts=$(git -C "$wt" diff --name-only --diff-filter=U) || exit 1
    [ -n "$conflicts" ] || exit 1
    while IFS= read -r file; do
      git -C "$wt" diff -- "$file" || exit 1
      answer=$(choose "$file" 'keep mine' 'keep theirs') || exit 1
      case "$answer" in
        'keep mine') side=ours ;; 'keep theirs') side=theirs ;; *) exit 1 ;;
      esac
      # A modify/delete conflict may have no blob on the chosen side.
      stage=2
      [ "$side" != theirs ] || stage=3
      if git -C "$wt" cat-file -e ":$stage:$file" 2>/dev/null; then
        git -C "$wt" checkout "--$side" -- "$file" || exit 1
        git -C "$wt" add -- "$file" || exit 1
      else
        git -C "$wt" rm -- "$file" || exit 1
      fi
    done <<< "$conflicts"
    git -C "$wt" commit --no-edit || exit 1
  fi
  if ! smm_run_validate "$wt"; then
    warn "incoming change breaks ${SMM_FAILED_LINKS:-config}; this Mac stays as is"
    exit 1
  fi
  merged=$(git -C "$wt" rev-parse HEAD) || exit 1
  git -C "$repo" merge --ff-only "$merged" || exit 1
)
