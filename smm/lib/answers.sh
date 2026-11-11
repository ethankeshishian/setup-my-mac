#!/usr/bin/env bash

smm_signal() {
  local line="$1: $2" state
  state=$(smm_state_dir) || return 1
  printf '%s\n' "$line" >> "$state/needs.log" || return 1
  printf '%s\n' "$line" >&2
}
smm_answer_value() {
  [ -n "${SMM_ANSWERS:-}" ] || return 0
  jq -er --arg key "$1" '
    if type != "object" then error("answers must be an object") else
      if has("questions") then
        [.questions[] | select(.key == $key)] |
        if length > 1 then error("duplicate answer") else .[0].value end
      else .[$key] end |
      if . == null then empty elif type == "string" and length > 0 then . else error("answer must be a nonempty string") end
    end' "$SMM_ANSWERS"
}
smm_answer() {
  local key=$1 question=$2 answer='' result=0 option valid=0
  shift 2
  answer=$(smm_answer_value "$key") || result=$?
  # jq returns 4 for an absent/null answer; every other error is invalid input.
  case "$result" in 0|4) ;; *) warn "invalid answers file: ${SMM_ANSWERS:-}"; return 1 ;; esac
  if [ -z "$answer" ]; then
    if ! smm_has_tty; then
      smm_signal SMM-NEEDS "answer $key: $question (allowed: $*)" || return 1
      return 3
    fi
    if [ "$*" = text ]; then
      printf '%s ' "$question" >&2
      IFS= read -r answer </dev/tty || return 1
    else answer=$(choose "$question" "$@") || return "$?"; fi
  fi
  if [ "$*" = text ]; then
    case "$answer" in *[![:space:]]*) valid=1 ;; esac
  else
    for option in "$@"; do [ "$answer" != "$option" ] || valid=1; done
  fi
  [ "$valid" -eq 1 ] || { warn "invalid answer $key: $answer (allowed: $*)"; return 1; }
  printf '%s\n' "$answer"
}
smm_setup_confirm() {
  local answer
  if [ -z "${SMM_ANSWERS:-}" ] && smm_has_tty; then confirm "$2"; return "$?"; fi
  answer=$(smm_answer "$1" "$2" yes no) || return "$?"
  [ "$answer" = yes ]
}
# Acknowledge only actions that cannot be detected. Detectable actions always
# check the actual app state, even when an answers file claims they are done.
smm_user_wait() {
  local key=$1 instruction=$2 checker=${3:-} elapsed=0 limit=${SMM_WAIT_SECONDS:-600} answer result=0
  shift 3
  answer=$(smm_answer_value "user.$key") || result=$?
  case "$result" in 0|4) ;; *) warn "invalid answer user.$key"; return 1 ;; esac
  case "$answer" in done|'') ;; *) warn "invalid answer user.$key: $answer (allowed: done)"; return 1 ;; esac
  if [ -z "$checker" ]; then
    [ "$answer" != "done" ] || return 0
    if smm_has_tty; then SMM_YES=0 confirm "$instruction"; return "$?"; fi
  else
    "$checker" "$@" && return 0
  fi
  smm_signal SMM-WAITING "$instruction" || return 1
  case "$limit" in ''|*[!0-9]*) warn 'invalid SMM_WAIT_SECONDS'; return 1 ;; esac
  if [ -n "$checker" ]; then
    while [ "$elapsed" -lt "$limit" ]; do
      sleep 2
      "$checker" "$@" && return 0
      elapsed=$((elapsed + 2))
    done
  fi
  smm_signal SMM-NEEDS "user $key: $instruction" || return 1
  return 3
}
# Third-party installers may call sudo internally. Give only that process a
# private shim; never replace the system sudo or expose a password to the shell.
smm_installer_run() (
  if smm_has_tty; then
    case "$1" in *.sh|*/installer) sh "$@" ;; *) "$@" ;; esac
    exit "$?"
  fi
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  actual_sudo=$(command -v sudo) || exit 1
  SUDO_ASKPASS="$(smm_resource_root)/libexec/askpass" || exit 1
  export SMM_INSTALLER_SUDO="$actual_sudo" SUDO_ASKPASS
  cat > "$tmp/sudo" <<'SHIM'
#!/usr/bin/env bash
exec "$SMM_INSTALLER_SUDO" -A "$@"
SHIM
  chmod +x "$tmp/sudo" || exit 1
  export PATH="$tmp:$PATH"
  case "$1" in *.sh|*/installer) sh "$@" ;; *) "$@" ;; esac
)
