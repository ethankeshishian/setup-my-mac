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
  changed=$(git diff-tree --root --no-commit-id --name-only -r "$upgrade") || exit 1
  if [ -z "$changed" ]; then
    # Cask-only upgrades have no reversible tree diff. Record the same footer
    # as git revert so the next undo can find the preceding upgrade.
    subject=$(git show -s --format=%s "$upgrade") || exit 1
    git commit --allow-empty -m "Revert \"$subject\"" -m "This reverts commit $upgrade." || exit 1
  elif ! git revert --no-edit "$upgrade"; then
    git revert --abort || warn 'could not abort revert'
    warn 'later changes touch the same lock files; undo by hand'
    exit 1
  fi
  smm_run_apply && smm_nvim_run '+Lazy! restore' || exit 1
  case "$body" in *'casks:'*) log "Homebrew app versions can't be reverted" ;; esac
)
