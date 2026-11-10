#!/usr/bin/env bash

smm_brewfile() {
  local state
  state=$(smm_state_dir) || return 1
  jq -r '(.taps[] | "tap " + tojson), (.brews[] | "brew " + tojson), (.casks[] | "cask " + tojson)' \
    "$(smm_repo)/manifest/homebrew.json" > "$state/Brewfile" || return 1
  printf '%s/Brewfile\n' "$state"
}
smm_brew_undeclared() {
  command -v brew >/dev/null 2>&1 || return 0
  local file output parsed status=0
  file=$(smm_brewfile) || return 1
  # Recent bundle versions prompt on a TTY. Closed stdin guarantees a dry run.
  output=$(HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_COLOR=1 brew bundle cleanup "--file=$file" </dev/null 2>&1) || status=$?
  parsed=$(awk '
    /^Would uninstall (formulae|formulas|brews):/ { kind="brew"; next }
    /^Would uninstall casks:/ { kind="cask"; next }
    /^Would untap:/ { kind="tap"; next }
    /^Would / { kind=""; next }
    /^[[:space:]]*$/ { next }
    kind != "" {
      for (i=1; i<=NF; i++) {
        if ($i !~ /^[a-zA-Z0-9][a-zA-Z0-9_+@.\/-]*$/) { kind=""; break }
      }
      if (kind != "") for (i=1; i<=NF; i++) print kind " " $i
    }
  ' <<< "$output") || return 1
  if [ "$status" -ne 0 ] && { [ "$status" -ne 1 ] || [ -z "$parsed" ]; }; then
    warn "$output"
    return "$status"
  fi
  [ -z "$parsed" ] || printf '%s\n' "$parsed"
  return 0
}
smm_brew_add() {
  local kind=$1 name=$2 field file tmp
  case "$kind" in brew) field=brews ;; cask) field=casks ;; tap) field=taps ;; *) return 2 ;; esac
  case "$name" in ''|-*|*[!a-zA-Z0-9_+@./-]*) return 2 ;; esac
  file="$(smm_repo)/manifest/homebrew.json"
  tmp=$(mktemp "$file.XXXXXX") || return 1
  if jq --arg field "$field" --arg name "$name" '.[$field] = ((.[$field] + [$name]) | unique | sort)' "$file" > "$tmp"; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    return 1
  fi
}
smm_brew_interactive() { [ "${SMM_YES:-0}" != 1 ] && smm_has_tty; }
smm_brew_resolve() {
  local packages kind name answer
  packages=$(smm_brew_undeclared) || return 1
  if [ -n "${SMM_BREW_EXCLUDE:-}" ]; then
    packages=$(printf '%s\n' "$packages" | grep -Fvx -f <(printf '%s\n' "$SMM_BREW_EXCLUDE")) || packages=''
  fi
  [ -n "$packages" ] || return 0
  if [ "${1:-}" = --list-only ]; then printf '%s\n' "$packages"; return 0; fi
  if ! smm_brew_interactive; then warn "undeclared Homebrew packages (unchanged):
$packages"; return 0; fi
  while IFS=' ' read -r kind name; do
    answer=$(choose "$kind $name is installed but not in your setup" 'add to setup' remove skip) || return 1
    case "$answer" in
      'add to setup') smm_brew_add "$kind" "$name" || return 1 ;;
      remove)
        case "$kind" in
          brew) HOMEBREW_NO_AUTOREMOVE=1 brew uninstall "$name" || return 1 ;;
          cask) HOMEBREW_NO_AUTOREMOVE=1 brew uninstall --cask "$name" || return 1 ;;
          tap) brew untap "$name" || return 1 ;;
        esac ;;
      skip) ;;
      *) return 1 ;;
    esac
  done <<< "$packages"
}
