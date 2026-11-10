#!/usr/bin/env bash

smm_migrate_file_status() {
  local source=$1 target=$2 repo blob head sha time mtime
  repo=$(smm_repo)
  if [ ! -e "$target" ] && [ ! -L "$target" ]; then printf 'repo-newer\n'; return; fi
  if [ ! -f "$target" ]; then printf 'both-changed\n'; return; fi
  blob=$(git -C "$repo" hash-object -- "$target") || return 1
  head=$(git -C "$repo" rev-parse "HEAD:$source" 2>/dev/null) || head=''
  if [ "$blob" = "$head" ]; then printf 'same\n'; return; fi
  while IFS= read -r sha; do
    if [ "$blob" = "$(git -C "$repo" rev-parse "$sha:$source" 2>/dev/null)" ]; then
      printf 'repo-newer\n'; return
    fi
  done < <(git -C "$repo" log --format=%H -- "$source")
  time=$(git -C "$repo" log -1 --format=%ct -- "$source") || return 1
  mtime=$(stat -f %m "$target" 2>/dev/null) || mtime=$(stat -c %Y "$target") || return 1
  if [ "${time:-0}" -gt "$mtime" ]; then printf 'both-changed\n'; else printf 'local-newer\n'; fi
}

smm_migrate_status() (
  name=$1 repo=$(smm_repo)
  source=$(link_field "$name" source) && target=$(link_field "$name" target) || exit 1
  smm_safe_relative "$target" && smm_config_source_safe "$source" || exit 1
  live="$HOME/$target"
  if [ -L "$live" ] && [ "$live" -ef "$repo/$source" ]; then echo linked; exit 0; fi
  if [ ! -e "$live" ] && [ ! -L "$live" ]; then echo missing; exit 0; fi
  if [ ! -d "$live" ] || [ ! -d "$repo/$source" ]; then
    smm_migrate_file_status "$source" "$live"; exit "$?"
  fi
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  # Include deleted files and local additions, but never nested git metadata.
  git -C "$repo" ls-tree -r --name-only HEAD -- "$source/" | while IFS= read -r path; do
    printf '%s\n' "${path#"$source/"}"
  done > "$tmp/files"
  (cd "$live" && find . -name .git -prune -o \( -type f -o -type l \) -print) | sed 's|^./||' >> "$tmp/files"
  LC_ALL=C sort -u "$tmp/files" > "$tmp/sorted"
  worst=same rank=0
  while IFS= read -r file; do
    status=$(smm_migrate_file_status "$source/$file" "$live/$file") || exit 1
    case "$status" in same) n=0 ;; repo-newer) n=1 ;; local-newer) n=2 ;; *) n=3 ;; esac
    if [ "$n" -gt "$rank" ]; then rank=$n; worst=$status; fi
  done < "$tmp/sorted"
  echo "$worst"
)

# Output uses the same brew/cask vocabulary as the drift helpers.
smm_brew_duplicates() {
  command -v brew >/dev/null 2>&1 || return 0
  local packages kind name short candidate alias installed
  packages=$(jq -r '.[]' "$(smm_repo)/manifest/nix-packages.json") || return 1
  for kind in brew cask; do
    if [ "$kind" = brew ]; then
      installed=$(brew list --formula) || return 1
    else
      installed=$(brew list --cask) || return 1
    fi
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      short=${name##*/}
      while IFS= read -r candidate; do
        alias=${candidate##*.}
        case "$candidate" in jankyborders) alias=borders ;; ghostty-bin) alias=ghostty@tip ;; esac
        if [ "$short" = "$alias" ] || [ "$short" = "$candidate" ]; then printf '%s %s\n' "$kind" "$name"; break; fi
      done <<< "$packages"
    done <<< "$installed"
  done
}

smm_migrate_preview() (
  # Brewfile generation is isolated too: preview leaves HOME and the repo untouched.
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  export SMM_STATE="$tmp/state"
  names=$(link_names) || exit 1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    status=$(smm_migrate_status "$name") || exit 1
    printf '%s %s\n' "$name" "$status"
  done <<< "$names"
  log 'Undeclared Homebrew packages:'
  smm_brew_undeclared || exit 1
  log 'Homebrew duplicates of Nix packages:'
  smm_brew_duplicates || exit 1
)

smm_migrate_resolve() (
  name=$1 repo=$(smm_repo)
  status=$(smm_migrate_status "$name") || exit 1
  case "$status" in linked|missing|same) exit 0 ;; esac
  source=$(link_field "$name" source) && target=$(link_field "$name" target) || exit 1
  live="$HOME/$target"
  # An unmanaged symlink needs explicit inspection; do not import external links.
  [ ! -L "$live" ] || { warn "inspect unmanaged symlink: $live"; exit 1; }
  log "$name differences (repo to this Mac):"
  if diff -ru -x .git -x '*.env.sh' -- "$repo/$source" "$live"; then
    :
  else
    [ "$?" -eq 1 ] || exit 1
  fi
  if [ "$status" = repo-newer ]; then answer='use repo';
  else answer=$(choose "$name: $status" 'use repo' 'use this Mac' 'pick changes') || exit 1; fi
  backup=$(smm_backup_dir) || exit 1
  mkdir -p "$backup/$(dirname "$target")" || exit 1
  # Never overwrite an earlier migration backup when setup resumes.
  saved="$backup/$target"
  if [ -e "$saved" ] || [ -L "$saved" ]; then saved=$(mktemp -d "$backup/retry.XXXXXX")/original; fi
  cp -a "$live" "$saved" || exit 1
  case "$answer" in
    'use repo') ;;
    'use this Mac'|'pick changes')
      tmp=$(mktemp -d) || exit 1
      trap 'rm -rf "$tmp"' EXIT
      cp -a "$live" "$tmp/config" || exit 1
      if [ -d "$tmp/config" ]; then
        rm -rf "$tmp/config/.git"
        if [ "$name" = nvim ] && [ -f "$tmp/config/lazy-lock.json" ] && [ -f "$repo/$source/lazy-lock.json" ]; then
          cp "$repo/$source/lazy-lock.json" "$tmp/repo-lock.json" || exit 1
          smm_migrate_lazylock "$tmp/config/lazy-lock.json" "$tmp/repo-lock.json" || exit 1
          cp "$tmp/repo-lock.json" "$tmp/config/lazy-lock.json" || exit 1
        fi
      fi
      rm -rf "${repo:?}/${source:?}" || exit 1
      cp -a "$tmp/config" "$repo/$source" || exit 1
      if [ "$answer" = 'pick changes' ]; then
        git -C "$repo" add -p -- "$source" || exit 1
        git -C "$repo" checkout -- "$source" || exit 1
        # checkout leaves new, unselected files untracked; drop only additions from this copy.
        git -C "$repo" ls-files --others --exclude-standard -- "$source" > "$tmp/untracked"
        while IFS= read -r file; do rm -f "$repo/$file" || exit 1; done < "$tmp/untracked"
      fi ;;
    *) exit 1 ;;
  esac
  log "$name: $answer; backup: $saved"
)

smm_migrate_lazylock() (
  local_lock=$1 repo_lock=$2
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  cp "$repo_lock" "$tmp/result" || exit 1
  plugins=$(jq -r 'keys[]' "$local_lock") || exit 1
  while IFS= read -r plugin; do
    smm_safe_relative "$plugin" || exit 1
    local_sha=$(jq -r --arg p "$plugin" '.[$p].commit // empty' "$local_lock") || exit 1
    repo_sha=$(jq -r --arg p "$plugin" '.[$p].commit // empty' "$repo_lock") || exit 1
    plugin_dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy/$plugin"
    if [ -n "$repo_sha" ] && [ -n "$local_sha" ] && [ -d "$plugin_dir/.git" ] &&
        git -C "$plugin_dir" merge-base --is-ancestor "$repo_sha" "$local_sha" 2>/dev/null; then
      jq --arg p "$plugin" --slurpfile local "$local_lock" '.[$p] = $local[0][$p]' "$tmp/result" > "$tmp/next" || exit 1
      mv "$tmp/next" "$tmp/result" || exit 1
    fi
  done <<< "$plugins"
  cp "$tmp/result" "$repo_lock"
)
