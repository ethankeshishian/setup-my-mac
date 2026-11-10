#!/usr/bin/env bash

smm_repo() { printf '%s\n' "${SMM_REPO:-$HOME/Repos/setup-my-mac}"; }
smm_state_dir() {
  local state=${SMM_STATE:-$HOME/.local/state/smm}
  mkdir -p "$state" || return
  printf '%s\n' "$state"
}
log() { printf '%s\n' "$*"; }
warn() { printf 'smm: %s\n' "$*" >&2; }
die() { warn "$1"; exit "${2:-1}"; }
confirm() {
  local answer
  [ "${SMM_YES:-0}" = 1 ] && return 0
  [ -t 0 ] || return 1
  printf '%s [y/N] ' "$1" >&2
  IFS= read -r answer || return 1
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
choose() {
  local question=$1 option answer index=0
  shift
  [ -t 0 ] || return 1
  printf '%s\n' "$question" >&2
  for option in "$@"; do
    index=$((index + 1))
    printf '%s) %s\n' "$index" "$option" >&2
  done
  IFS= read -r answer || return 1
  case "$answer" in ''|*[!0-9]*) return 1 ;; esac
  [ "$answer" -gt 0 ] && [ "$answer" -le "$#" ] || return 1
  index=0
  for option in "$@"; do
    index=$((index + 1))
    if [ "$index" -eq "$answer" ]; then printf '%s\n' "$option"; return 0; fi
  done
}
links_json() { cat "$(smm_repo)/manifest/links.json"; }
link_field() {
  links_json | jq -er --arg name "$1" --arg field "$2" '.[] | select(.name == $name) | .[$field] // empty'
}
link_names() { links_json | jq -r '.[].name'; }
