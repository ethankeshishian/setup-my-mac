#!/usr/bin/env bash

cmd_status() {
  local repo changes counts ahead behind packages name source target secrets any=0
  repo=$(smm_repo)
  changes=$(git -C "$repo" status --short) || return 1
  if [ -n "$changes" ]; then printf 'uncommitted changes:\n%s\n' "$changes"; any=1; fi
  # No remote is normal for a new local checkout. Offline status remains useful.
  if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    if git -C "$repo" fetch --quiet origin 2>/dev/null; then
      if counts=$(git -C "$repo" rev-list --left-right --count HEAD...origin/main 2>/dev/null); then
        read -r ahead behind <<< "$counts"
        if [ "$ahead" -ne 0 ] || [ "$behind" -ne 0 ]; then
          printf 'origin/main: %s ahead, %s behind\n' "$ahead" "$behind"; any=1
        fi
      fi
    else printf 'remote: offline (ahead/behind unavailable)\n'; any=1; fi
  fi
  if packages=$(smm_brew_undeclared); then
    if [ -n "$packages" ]; then printf 'undeclared Homebrew packages:\n%s\n' "$packages"; any=1; fi
  else printf 'Homebrew status unavailable\n'; any=1; fi
  changes=''
  while IFS=$'\t' read -r name source target; do
    [ -n "$name" ] || continue
    if ! smm_linked_to "$HOME/$target" "$repo/$source"; then
      changes="${changes}${name}: ~/${target}"$'\n'
    fi
  done < <(jq -r '.[] | [.name,.source,.target] | @tsv' "$repo/manifest/links.json")
  if [ -n "$changes" ]; then printf 'broken links:\n%s' "$changes"; any=1; fi
  secrets=$(jq -r '.[] | [.name,.target] | @tsv' "$repo/manifest/secrets.json") || return 1
  changes=''
  while IFS=$'\t' read -r name target; do
    [ -n "$name" ] || continue
    [ -f "$HOME/$target" ] || changes="${changes}missing secret: $name"$'\n'
  done <<< "$secrets"
  if ! gh auth status >/dev/null 2>&1; then changes="${changes}GitHub not signed in (push disabled)"$'\n'; fi
  if [ -f "$(smm_state_dir)/signin-skipped" ] && ! op whoami >/dev/null 2>&1; then
    changes="${changes}1Password not signed in (weather disabled)"$'\n'
  fi
  if [ -n "$changes" ]; then printf 'degraded items:\n%s' "$changes"; any=1; fi
  [ "$any" -ne 0 ] || printf 'clean\n'
  return 0
}
