#!/usr/bin/env bash

smm_setup_steps() {
  # shellcheck disable=SC2034 # Consumed by cmd_setup in cmd/setup.sh.
  SETUP_STEPS=(preflight nix host preview configs brew_adopt build dedupe switch permissions signin secrets nvim health commit finish)
}

smm_permission_granted() {
  case "$1" in
    aerospace) aerospace list-workspaces --all >/dev/null 2>&1 ;;
    karabiner)
      local extensions
      extensions=$(systemextensionsctl list 2>/dev/null) || return "$?"
      grep -Eiq 'pqrs.*\[activated enabled\]' <<< "$extensions" ;;
    *) return 2 ;;
  esac
}
smm_wait_permission() {
  local app=$1 checker label check_status=0
  case "$app" in
    aerospace) checker=aerospace; label=Accessibility ;;
    karabiner) checker=systemextensionsctl; label='driver approval and Input Monitoring' ;;
    *) warn "unknown permission check: $app"; return 2 ;;
  esac
  smm_permission_granted "$app" && return 0
  check_status=$?
  warn "Grant $app $label in System Settings."
  case "$app" in
    aerospace) open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility' || return 1 ;;
    karabiner)
      open 'x-apple.systempreferences:com.apple.LoginItems-Settings.extension?ExtensionItems' || return 1
      open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent' || return 1 ;;
  esac
  if [ "$check_status" -eq 127 ] || ! command -v "$checker" >/dev/null 2>&1; then confirm 'Done?'; return "$?"; fi
  # A noninteractive caller cannot grant permission; fail with the pane open.
  [ -t 0 ] || return 1
  while ! smm_permission_granted "$app"; do sleep 2; done
}
smm_need_restart() {
  local file
  file="$(smm_state_dir)/restart-needed" || return 1
  if [ ! -f "$file" ] || ! grep -Fxq -- "$1" "$file"; then printf '%s\n' "$1" >> "$file"; fi
}

step_preflight_done() {
  [ "$(uname -m)" = arm64 ] &&
    [ "$(cd "$(smm_repo)" && pwd -P)" = "$HOME/Repos/setup-my-mac" ] &&
    [ "$(git -C "$(smm_repo)" branch --show-current)" = main ]
}
step_preflight_run() {
  step_preflight_done || { warn 'requires arm64, ~/Repos/setup-my-mac, and branch main'; return 1; }
}
step_nix_done() {
  command -v nix >/dev/null 2>&1 && nix --version >/dev/null 2>&1 && nix store ping --store daemon >/dev/null 2>&1
}
step_nix_run() {
  if [ -x /nix/nix-installer ]; then
    /nix/nix-installer repair || return 1
  else
    (
      tmp=$(mktemp -d) || exit 1
      trap 'rm -rf "$tmp"' EXIT
      curl -fsSL https://install.determinate.systems/nix -o "$tmp/installer" || exit 1
      sh "$tmp/installer" install
    ) || return 1
  fi
  if ! command -v nix >/dev/null 2>&1 && [ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then
    # shellcheck source=/dev/null
    source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
  fi
  step_nix_done
}

step_host_done() {
  local host
  host=$(smm_host) || return 1
  [ -f "$(smm_repo)/hosts/$host.nix" ] && [ "$host" != template ] &&
    git -C "$(smm_repo)" ls-files --error-unmatch "hosts/$host.nix" >/dev/null 2>&1
}
step_host_run() {
  local current host repo
  repo=$(smm_repo); current=$(smm_host) || return 1
  printf 'Host name [%s]: ' "$current" >&2
  IFS= read -r host || return 1
  host=${host:-$current}
  case "$host" in ''|*[!a-zA-Z0-9-]*|-*|template) warn 'invalid host name'; return 1 ;; esac
  [ "${#host}" -le 63 ] || return 1
  if [ ! -f "$repo/hosts/$host.nix" ]; then
    sed "s/HOSTNAME/$host/g" "$repo/hosts/template.nix" > "$repo/hosts/$host.nix" || return 1
  fi
  # Git flakes exclude untracked host files. Commit only this host, leaving
  # any interrupted migration changes for the final setup commit.
  if ! git -C "$repo" ls-files --error-unmatch "hosts/$host.nix" >/dev/null 2>&1; then
    git -C "$repo" add -- "hosts/$host.nix" || return 1
    git -C "$repo" commit --only -m "Add host $host" -- "hosts/$host.nix" || return 1
  fi
  export SMM_HOST="$host"
}
step_preview_done() { return 1; }
step_preview_run() { smm_migrate_preview && confirm 'Continue?'; }
step_configs_done() {
  local names name status
  names=$(link_names) || return 1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    status=$(smm_migrate_status "$name") || return 1
    case "$status" in linked|missing) ;; *) return 1 ;; esac
  done <<< "$names"
}
step_configs_run() {
  local names name status target backup saved
  names=$(link_names) || return 1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    status=$(smm_migrate_status "$name") || return 1
    if [ "$status" = same ]; then
      # The migration resolver deliberately leaves identical files alone.
      # Activation still needs the real target cleared, with its own backup.
      target=$(link_field "$name" target) || return 1
      backup=$(smm_backup_dir) || return 1
      mkdir -p "$backup/$(dirname "$target")" || return 1
      saved="$backup/$target"
      if [ -e "$saved" ] || [ -L "$saved" ]; then saved=$(mktemp -d "$backup/retry.XXXXXX")/original; fi
      cp -a "$HOME/$target" "$saved" || return 1
      rm -rf "${HOME:?}/${target:?}" || return 1
    else smm_migrate_resolve "$name" || return 1; fi
  done <<< "$names"
}

smm_setup_prune_duplicates() {
  local duplicates kind name field file tmp
  duplicates=$(smm_brew_duplicates) || return 1
  file="$(smm_repo)/manifest/homebrew.json"
  while IFS=' ' read -r kind name; do
    [ -n "$name" ] || continue
    case "$kind" in brew) field=brews ;; cask) field=casks ;; *) return 1 ;; esac
    tmp=$(mktemp) || return 1
    if ! jq --arg field "$field" --arg name "$name" '.[$field] -= [$name]' "$file" > "$tmp"; then rm -f "$tmp"; return 1; fi
    cp "$tmp" "$file" || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
  done <<< "$duplicates"
}
step_brew_adopt_done() {
  local packages duplicates
  packages=$(smm_brew_undeclared) || return 1
  duplicates=$(smm_brew_duplicates) || return 1
  [ -z "$packages" ] && [ -z "$duplicates" ]
}
step_brew_adopt_run() {
  local SMM_BREW_EXCLUDE
  # shellcheck disable=SC2034 # Dynamically scoped input to smm_brew_resolve.
  SMM_BREW_EXCLUDE=$(smm_brew_duplicates) || return 1
  # Nix duplicates are removed only after the replacement has built successfully.
  smm_setup_prune_duplicates && smm_brew_resolve
}
step_build_done() {
  local state hash path
  state=$(smm_state_dir) || return 1
  [ -f "$state/last-build" ] && [ -f "$state/setup-build.hash" ] || return 1
  path=$(cat "$state/last-build")
  [ -d "$path" ] || return 1
  hash=$(smm_nix_inputs_hash) || return 1
  [ "$hash" = "$(cat "$state/setup-build.hash")" ]
}
step_build_run() {
  smm_build || return 1
  smm_nix_inputs_hash > "$(smm_state_dir)/setup-build.hash"
}
step_dedupe_done() {
  local duplicates
  duplicates=$(smm_brew_duplicates) || return 1
  [ -z "$duplicates" ]
}
step_dedupe_run() {
  local duplicates kind name file
  duplicates=$(smm_brew_duplicates) || return 1
  file="$(smm_state_dir)/deduped"
  while IFS=' ' read -r kind name; do
    [ -n "$name" ] || continue
    # Journal before stopping anything so interruption is recoverable.
    if [ ! -f "$file" ] || ! grep -Fxq "$kind $name" "$file"; then printf '%s %s\n' "$kind" "$name" >> "$file"; fi
    case "$kind" in
      brew) brew services stop "$name" || :; HOMEBREW_NO_AUTOREMOVE=1 brew uninstall "$name" || return 1 ;;
      cask)
        osascript -e 'on run argv' -e 'tell application (item 1 of argv) to quit' -e 'end run' "$name" || :
        HOMEBREW_NO_AUTOREMOVE=1 brew uninstall --cask "$name" || return 1 ;;
      *) return 1 ;;
    esac
  done <<< "$duplicates"
}
smm_setup_restore_brew() {
  local file kind name failed=0
  file="$(smm_state_dir)/deduped"
  [ -s "$file" ] || return 0
  while IFS=' ' read -r kind name; do
    case "$kind" in
      brew) brew install "$name" && brew services start "$name" || failed=1 ;;
      cask) brew install --cask "$name" && open -a "$name" || failed=1 ;;
      *) failed=1 ;;
    esac
  done < "$file"
  [ "$failed" -ne 0 ] || : > "$file"
  return "$failed"
}
smm_setup_recover() {
  local file failed=0
  export PATH="${SMM_SETUP_ORIGINAL_PATH:-$PATH}"
  file="$(smm_state_dir)/setup-generation"
  if [ -s "$file" ]; then
    smm_rollback "$(cat "$file")" || failed=1
    smm_reload || :
    [ "$failed" -ne 0 ] || rm -f "$file"
  fi
  smm_setup_restore_brew || failed=1
  return "$failed"
}
step_switch_done() { ! smm_nix_changed && step_configs_linked; }
step_configs_linked() {
  local name names
  names=$(link_names) || return 1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ "$(smm_migrate_status "$name")" = linked ] || return 1
  done <<< "$names"
}
step_switch_run() {
  local state
  state=$(smm_state_dir) || return 1
  smm_use_build_tools && smm_run_validate "$(smm_repo)" || return 1
  smm_generation > "$state/setup-generation" || return 1
  if ! smm_switch; then smm_setup_recover || warn 'recovery incomplete'; return 1; fi
  smm_need_restart 'macOS menu bar and symbolic hotkey defaults' || return 1
}
step_permissions_done() { smm_permission_granted aerospace && smm_permission_granted karabiner; }
step_permissions_run() {
  smm_wait_permission aerospace || return 1
  smm_wait_permission karabiner
}
step_signin_done() { op whoami >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; }
step_signin_run() {
  local file
  file="$(smm_state_dir)/signin-skipped"
  : > "$file"
  if ! op whoami >/dev/null 2>&1; then
    if [ -t 0 ] && confirm 'Sign in to 1Password now?'; then
      open -a '1Password' || return 1
      while ! op whoami >/dev/null 2>&1; do
        confirm 'Enable 1Password CLI integration. Done (or cancel to skip)?' || break
      done
    fi
    op whoami >/dev/null 2>&1 || printf '1Password not signed in (weather disabled)\n' >> "$file"
  fi
  if ! gh auth status >/dev/null 2>&1; then
    if [ -t 0 ] && confirm 'Sign in to GitHub now?'; then gh auth login || :; fi
    gh auth status >/dev/null 2>&1 || printf 'GitHub not signed in (push disabled)\n' >> "$file"
  fi
  if [ -s "$file" ]; then warn "degraded: $(cat "$file")"; fi
  return 0
}
step_secrets_done() {
  local target targets
  targets=$(jq -r '.[].target' "$(smm_repo)/manifest/secrets.json") || return 1
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    [ -f "$HOME/$target" ] || return 1
  done <<< "$targets"
}
# Keep entered values out of command arguments, setup.log, and the repository.
smm_setup_read_secret() {
  local value
  printf 'Paste the secret field contents (one line): ' >&2
  IFS= read -r -s value || return 1
  printf '\n' >&2
  [ -n "$value" ] || return 1
  printf '%s\n' "$value" > "$1"
}
step_secrets_run() (
  umask 077
  op whoami >/dev/null 2>&1 || { smm_secrets_materialize; exit "$?"; }
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/repo/manifest" || exit 1
  printf '[]\n' > "$tmp/repo/manifest/secrets.json"
  entries=$(jq -c '.[]' "$(smm_repo)/manifest/secrets.json") || exit 1
  skipped="$(smm_state_dir)/secrets-skipped"
  : > "$skipped"
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    name=$(jq -er .name <<< "$entry") && target=$(jq -er .target <<< "$entry") &&
      ref=$(jq -er .op_ref <<< "$entry") || exit 1
    if [ ! -f "$HOME/$target" ]; then
      case "$ref" in op://*/*/*) ;; *) warn "invalid 1Password reference: $name"; exit 1 ;; esac
      path=${ref#op://}; vault=${path%%/*}; path=${path#*/}; item=${path%%/*}; field=${path#*/}
      if ! op item get "$item" --vault "$vault" --format json >/dev/null 2>&1; then
        if ! confirm "Create missing 1Password item $vault/$item for $name?"; then
          printf '%s secret not configured\n' "$name" >> "$skipped"
          continue
        fi
        if ! op vault get "$vault" >/dev/null 2>&1; then op vault create "$vault" >/dev/null 2>&1 || exit 1; fi
        smm_setup_read_secret "$tmp/value" || exit 1
        # 1Password's item JSON template keeps the value on stdin, never argv.
        jq -n --arg title "$item" --arg field "$field" --rawfile value "$tmp/value" \
          '{title:$title,category:"SECURE_NOTE",fields:[{id:$field,label:$field,type:"CONCEALED",value:$value}]}' > "$tmp/item.json" || exit 1
        op item create - --vault "$vault" < "$tmp/item.json" >/dev/null 2>&1 || { warn "could not create $name item"; exit 1; }
      fi
    fi
    jq --argjson entry "$entry" '. + [$entry]' "$tmp/repo/manifest/secrets.json" > "$tmp/next.json" || exit 1
    mv "$tmp/next.json" "$tmp/repo/manifest/secrets.json" || exit 1
  done <<< "$entries"
  SMM_REPO="$tmp/repo" smm_secrets_materialize
)
step_nvim_done() {
  local plugin sha dir entries
  dir="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"
  entries=$(jq -r 'to_entries[] | [.key,.value.commit] | @tsv' "$(smm_repo)/config/nvim/lazy-lock.json") || return 1
  while IFS=$'\t' read -r plugin sha; do
    [ -n "$plugin" ] || continue
    [ "$(git -C "$dir/$plugin" rev-parse HEAD 2>/dev/null)" = "$sha" ] || return 1
  done <<< "$entries"
  validate_nvim "$(smm_repo)/config/nvim"
}
step_nvim_run() {
  smm_nvim_run '+Lazy! restore' '+TSUpdateSync' || return 1
  validate_nvim "$(smm_repo)/config/nvim"
}
step_health_done() {
  # Finalize recovery only after the complete health check passes.
  smm_health || return 1
  rm -f "$(smm_state_dir)/setup-generation"
  : > "$(smm_state_dir)/deduped"
}
step_health_run() {
  if ! smm_health; then smm_setup_recover || warn 'recovery incomplete'; return 1; fi
  rm -f "$(smm_state_dir)/setup-generation"
  : > "$(smm_state_dir)/deduped"
}
step_commit_done() {
  local repo
  repo=$(smm_repo)
  [ -z "$(git -C "$repo" status --porcelain)" ] || return 1
  if gh auth status >/dev/null 2>&1 && git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    [ "$(git -C "$repo" rev-list --count origin/main..HEAD 2>/dev/null)" = 0 ] || return 1
  fi
}
step_commit_run() (
  cd "$(smm_repo)" || exit 1
  if [ -n "$(git status --porcelain)" ]; then
    smm_run_validate "$(smm_repo)" || exit 1
    printf 'Commit message: ' >&2
    IFS= read -r message || exit 1
    case "$message" in *[![:space:]]*) ;; *) warn 'empty commit message'; exit 1 ;; esac
    git add -A && git commit -m "$message" || exit 1
  fi
  if gh auth status >/dev/null 2>&1; then
    git fetch origin || exit 1
    smm_scan_outgoing origin/main..HEAD || exit 1
    git push origin HEAD:main || exit 1
  else warn 'GitHub not signed in; push disabled'; fi
)
step_finish_done() { return 1; }
step_finish_run() {
  local state
  state=$(smm_state_dir) || return 1
  log 'Setup complete. Still manual: App Store and iCloud sign-in.'
  [ ! -s "$state/signin-skipped" ] || cat "$state/signin-skipped"
  [ ! -s "$state/secrets-skipped" ] || cat "$state/secrets-skipped"
  if [ -s "$state/restart-needed" ]; then
    log 'Restart needed:'; cat "$state/restart-needed"
    if confirm 'Restart now?'; then osascript -e 'tell app "System Events" to restart'; fi
  fi
}
