#!/usr/bin/env bash

cmd_undo() (
  [ "$#" -eq 0 ] || { warn 'usage: smm undo'; exit 2; }
  cd "$(smm_repo)" || exit 1
  [ -z "$(git status --porcelain)" ] || { warn 'commit or sync first'; exit 1; }
  upgrade=''
  candidates=$(git log --format=%H --grep='^upgrade:' ) || exit 1
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    case "$(git show -s --format=%s "$sha")" in upgrade:*) ;; *) continue ;; esac
    # Match the exact revert footer, rather than potentially identical subjects.
    if ! git log --format=%B "$sha..HEAD" | grep -Fx "This reverts commit $sha." >/dev/null; then
      upgrade=$sha; break
    fi
  done <<< "$candidates"
  [ -n "$upgrade" ] || { warn 'no upgrade to undo'; exit 1; }
  body=$(git show -s --format=%b "$upgrade") || exit 1
  before=$(git rev-parse HEAD) || exit 1
  prev=$(smm_generation) || exit 1
  smm_tx_begin undo || exit 1
  complete=0 applying=0
  state=$(smm_state_dir) || exit 1
  # shellcheck disable=SC2329
  smm_undo_restore() {
    local recovered=0
    if [ "$complete" -eq 0 ]; then
      git revert --abort >/dev/null 2>&1 || :
      git reset --hard "$before" || recovered=1
      if [ "$applying" -eq 1 ]; then smm_rollback "$prev" || recovered=1; fi
      smm_tx_restore || recovered=1
      smm_nvim_run '+Lazy! restore' || warn 'previous plugin restore failed'
      if [ "$applying" -eq 1 ]; then smm_reload || :; fi
    fi
    [ "$recovered" -ne 0 ] || rm -rf "$SMM_TX"
  }
  trap smm_undo_restore EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  for file in applied.hash lazy-lock.hash lazy-lock.json; do smm_tx_arm "$state/$file" || exit 1; done
  smm_tx_arm "${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy" || exit 1
  # Stage the reverse diff, but make the revert commit only after activation.
  if ! git revert --no-commit "$upgrade"; then
    warn 'later changes touch the same lock files; undo by hand'
    exit 1
  fi
  applying=1
  smm_run_apply && smm_nvim_run '+Lazy! restore' || exit 1
  subject=$(git show -s --format=%s "$upgrade") || exit 1
  git commit --allow-empty -m "Revert \"$subject\"" -m "This reverts commit $upgrade." || exit 1
  complete=1
  case "$body" in *'casks:'*) log "Homebrew app versions can't be reverted" ;; esac
)
