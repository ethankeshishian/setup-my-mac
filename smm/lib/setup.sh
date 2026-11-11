#!/usr/bin/env bash

smm_setup_steps() {
  # shellcheck disable=SC2034 # Consumed by cmd_setup in cmd/setup.sh.
  SETUP_STEPS=(preflight host nix lock preview configs brew_adopt brew_existing build etc dedupe switch permissions signin raycast secrets nvim health commit finish)
}

smm_permission_granted() {
  case "$1" in
    aerospace) aerospace list-workspaces --all >/dev/null 2>&1 ;;
    karabiner)
      local extensions
      extensions=$(systemextensionsctl list 2>/dev/null) || return "$?"
      grep -Eiq 'pqrs.*\[activated enabled\]' <<< "$extensions" ;;
    alttab) return 2 ;; # macOS has no reliable per-app TCC query; confirm both grants.
    *) return 2 ;;
  esac
}
smm_wait_permission() {
  local app=$1 checker label check_status=0
  case "$app" in
    aerospace) checker=aerospace; label=Accessibility ;;
    karabiner) checker=systemextensionsctl; label='driver approval and Input Monitoring' ;;
    alttab)
      warn 'Grant AltTab Accessibility AND Screen Recording in System Settings.'
      open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility' || return 1
      open 'x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture' || return 1
      smm_user_wait alttab 'AltTab has Accessibility AND Screen Recording. Done?' ''
      return "$?" ;;
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
  if [ "$check_status" -eq 127 ] || ! command -v "$checker" >/dev/null 2>&1; then
    smm_user_wait "$app" "Grant $app $label in System Settings. Done?" ''
  elif ! smm_has_tty; then
    smm_user_wait "$app" "Grant $app $label in System Settings." smm_permission_granted "$app"
  else
    while ! smm_permission_granted "$app"; do sleep 2; done
  fi
}
smm_restart_pending() {
  local state boot recorded
  state=$(smm_state_dir) || return 1
  boot=$(sysctl -n kern.boottime) || return 1
  [ -s "$state/restart-needed" ] || return 1
  recorded=$(cat "$state/restart-boot" 2>/dev/null) || recorded=''
  if [ "$recorded" != "$boot" ]; then
    rm -f "$state/restart-needed" "$state/restart-boot"
    return 1
  fi
}
smm_need_restart() {
  local state boot
  state=$(smm_state_dir) || return 1
  boot=$(sysctl -n kern.boottime) || return 1
  smm_restart_pending || :
  printf '%s\n' "$boot" > "$state/restart-boot" || return 1
  if [ ! -f "$state/restart-needed" ] || ! grep -Fxq -- "$1" "$state/restart-needed"; then
    printf '%s\n' "$1" >> "$state/restart-needed"
  fi
}

step_preflight_done() {
  [ "$(uname -m)" = arm64 ] &&
    [ "$(cd "$(smm_repo)" && pwd -P)" = "$HOME/Repos/setup-my-mac" ] &&
    [ "$(git -C "$(smm_repo)" branch --show-current)" = main ]
}
step_preflight_run() {
  step_preflight_done || { warn 'requires arm64, ~/Repos/setup-my-mac, and branch main'; return 1; }
}
# Override only in isolated tests; production uses the installer's fixed paths.
smm_nix_root() { printf '%s\n' "${SMM_NIX_ROOT:-/nix}"; }
smm_nix_version_matches() {
  case "$1:$2" in
    lix:*Lix*) return 0 ;;
    determinate:*Lix*) return 1 ;;
    determinate:*) return 0 ;;
    *) return 1 ;;
  esac
}
step_nix_done() {
  local impl version
  command -v nix >/dev/null 2>&1 && version=$(smm_nix --version 2>/dev/null) || return 1
  impl=$(smm_nix_impl) || return 1
  smm_nix_version_matches "$impl" "$version" &&
    smm_nix store ping --store daemon >/dev/null 2>&1
}
smm_install_determinate() (
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL https://install.determinate.systems/nix -o "$tmp/installer" || exit 1
  smm_installer_run "$tmp/installer" install
)
smm_install_lix() (
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  curl -sSf -L https://install.lix.systems/lix -o "$tmp/installer" || exit 1
  smm_installer_run "$tmp/installer" install
)
step_nix_run() {
  local root impl version installed=0
  root=$(smm_nix_root) || return 1
  impl=$(smm_nix_impl) || return 1
  if command -v nix >/dev/null 2>&1; then
    version=$(smm_nix --version 2>/dev/null) || {
      warn 'Cannot identify the existing Nix implementation; repair it manually before rerunning setup. Setup never switches implementations or uninstalls Nix.'
      return 1
    }
    if ! smm_nix_version_matches "$impl" "$version"; then
      warn "Found $version, but host $(smm_host) requires $impl (manifest/hosts.json). Setup never switches implementations or uninstalls Nix."
      return 1
    fi
    smm_nix store ping --store daemon >/dev/null 2>&1 && return 0
    installed=1
  fi
  case "$impl" in
    determinate)
      if [ -x "$root/nix-installer" ]; then smm_installer_run "$root/nix-installer" repair || return 1
      else smm_install_determinate || return 1; fi ;;
    lix)
      if [ "$installed" -eq 0 ]; then smm_install_lix || return 1
      elif [ -x "$root/lix-installer" ]; then smm_installer_run "$root/lix-installer" repair || return 1
      else
        warn 'Lix is unhealthy and /nix/lix-installer is unavailable; repair Lix manually before rerunning setup.'
        return 1
      fi ;;
  esac
  if ! command -v nix >/dev/null 2>&1 && [ -f "$root/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
    # shellcheck source=/dev/null
    source "$root/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  fi
  step_nix_done
}

# The first Mac pins the flake inputs; every later Mac gets flake.lock from the repo.
step_lock_done() {
  git -C "$(smm_repo)" ls-files --error-unmatch flake.lock >/dev/null 2>&1
}
step_lock_run() {
  local repo
  repo=$(smm_repo)
  (cd "$repo" && smm_nix flake lock) || return 1
  git -C "$repo" add flake.lock &&
    git -C "$repo" commit -q -m 'Pin Nix inputs' -- flake.lock || return 1
  step_lock_done
}

step_host_done() {
  local host
  host=$(smm_host) || return 1
  [ -f "$(smm_repo)/config/zsh/$host.zshrc" ] &&
    [ -f "$(smm_repo)/hosts/$host.nix" ] && [ "$host" != template ] &&
    git -C "$(smm_repo)" ls-files --error-unmatch "hosts/$host.nix" >/dev/null 2>&1 &&
    jq -e --arg host "$host" '.[$host].nix | . == "determinate" or . == "lix"' \
      "$(smm_repo)/manifest/hosts.json" >/dev/null
}
smm_seed_host_zsh() {
  local host=$1 repo file common retired local_zsh
  case "$host" in ''|-*|*[!a-zA-Z0-9-]*) warn 'invalid host name'; return 1 ;; esac
  repo=$(smm_repo) || return 1
  file="config/zsh/$host.zshrc"
  smm_config_source_safe "$file" || return 1
  [ ! -e "$repo/$file" ] || return 0
  mkdir -p "$repo/config/zsh" || return 1
  common="$repo/config/zsh/common.zsh"
  [ -f "$common" ] || common=/dev/null
  retired="$repo/config/zsh/retired-shared.zsh"
  [ -f "$retired" ] || retired=/dev/null
  local_zsh="$HOME/.zshrc"
  [ -f "$local_zsh" ] || local_zsh=/dev/null
  {
    printf '%s\n' "# This Mac's own zsh setup. Shared settings live in ~/.config/zsh/common.zsh; anything below overrides them. Installers may append here." \
      '[ -f ~/.config/zsh/common.zsh ] && source ~/.config/zsh/common.zsh'
    # Match whole shared if-blocks, never individual fi/else lines. Keep an
    # unmatched local block intact, including shared-looking commands inside it.
    awk -v source_line='[ -f ~/.config/zsh/common.zsh ] && source ~/.config/zsh/common.zsh' '
      function normalize(line) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
        gsub(/[[:space:]]+/, " ", line)
        if (line == "export EDITOR=\047nvim\047" || line == "export EDITOR=\"nvim\"")
          line = "export EDITOR=nvim"
        return line
      }
      function flush() {
        if (reading_common) { if (key != "") shared[key] = 1 }
        else if (!(key in shared) && key != source_line) printf "%s", block
        block = ""; key = ""
      }
      FNR == 1 {
        flush()
        # Every file before the existing ~/.zshrc lists shared lines.
        reading_common = (FILENAME != ARGV[ARGC - 1])
      }
      {
        line = normalize($0)
        block = block $0 "\n"
        if (line == "" || line ~ /^#/) next
        key = key (key == "" ? "" : "\034") line
        if (line ~ /^if / && line !~ /;[[:space:]]*fi([[:space:]]|;|$)/) depth++
        if (line ~ /^fi([[:space:]]|;|$)/) depth--
        if (depth == 0) flush()
      }
      END { flush() }
    ' "$common" "$retired" "$local_zsh"
  } > "$repo/$file"
}
step_host_run() {
  local current host repo impl tmp
  repo=$(smm_repo); current=$(smm_host) || return 1
  if [ -n "${SMM_ANSWERS:-}" ] || ! smm_has_tty; then
    host=$(smm_answer host.name "Host name [$current]:" text) || return "$?"
  else
    printf 'Host name [%s]: ' "$current" >&2
    IFS= read -r host </dev/tty || return 1
  fi
  host=${host:-$current}
  case "$host" in ''|*[!a-zA-Z0-9-]*|-*|template) warn 'invalid host name'; return 1 ;; esac
  [ "${#host}" -le 63 ] || return 1
  impl=$(jq -r --arg host "$host" '.[$host].nix // empty' "$repo/manifest/hosts.json") || return 1
  if [ -z "$impl" ]; then
    if [ -n "${SMM_ANSWERS:-}" ] || ! smm_has_tty; then
      impl=$(smm_answer host.nix 'Choose Nix implementation' determinate lix) || return "$?"
    else impl=$(choose 'Choose Nix implementation' determinate lix) || return 1; fi
    case "$impl" in determinate|lix) ;; *) return 1 ;; esac
    tmp=$(mktemp "$repo/manifest/.hosts.XXXXXX") || return 1
    if ! jq --arg host "$host" --arg impl "$impl" '.[$host].nix = $impl' \
      "$repo/manifest/hosts.json" > "$tmp"; then rm -f "$tmp"; return 1; fi
    mv "$tmp" "$repo/manifest/hosts.json" || { rm -f "$tmp"; return 1; }
  fi
  case "$impl" in determinate|lix) ;; *) warn "invalid Nix implementation for $host: $impl"; return 1 ;; esac
  if [ ! -f "$repo/hosts/$host.nix" ]; then
    sed "s/HOSTNAME/$host/g" "$repo/hosts/template.nix" > "$repo/hosts/$host.nix" || return 1
  fi
  smm_seed_host_zsh "$host" || return 1
  # Git flakes exclude untracked host files. Commit only this host, leaving
  # any interrupted migration changes for the final setup commit.
  if ! git -C "$repo" ls-files --error-unmatch "hosts/$host.nix" >/dev/null 2>&1; then
    git -C "$repo" add -- "hosts/$host.nix" || return 1
    git -C "$repo" commit --only -m "Add host $host" -- "hosts/$host.nix" || return 1
  fi
  export SMM_HOST="$host"
}
step_preview_done() { return 1; }
step_preview_run() { smm_migrate_preview && smm_run_validate "$(smm_repo)" aerospace && smm_setup_confirm continue 'Continue?'; }
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
  local names name status target backup saved source
  [ -n "${SMM_TX:-}" ] || smm_tx_begin setup || return 1
  names=$(link_names) || return 1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    status=$(smm_migrate_status "$name") || return 1
    target=$(link_field "$name" target) || return 1
    smm_safe_relative "$target" || return 1
    smm_tx_watch "$HOME/$target" target || return 1
    source=$(link_source "$name") || return 1
    smm_config_source_safe "$source" || return 1
    if [ "$status" != linked ] && [ "$status" != missing ]; then
      smm_tx_arm "$(smm_repo)/$source" || return 1
    fi
    if [ "$status" = same ]; then
      # The migration resolver deliberately leaves identical files alone.
      # Activation still needs the real target cleared, with its own backup.
      target=$(link_field "$name" target) || return 1
      backup=$(smm_backup_dir) || return 1
      mkdir -p "$backup/$(dirname "$target")" || return 1
      saved="$backup/$target"
      if [ -e "$saved" ] || [ -L "$saved" ]; then saved=$(mktemp -d "$backup/retry.XXXXXX")/original; fi
      cp -a "$HOME/$target" "$saved" || return 1
    else smm_migrate_resolve "$name" || return "$?"; fi
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
  if [ -n "${SMM_TX:-}" ]; then smm_tx_arm "$(smm_repo)/manifest/homebrew.json" || return 1; fi
  smm_setup_prune_duplicates && smm_brew_resolve
}
step_brew_existing_done() {
  local unmanaged missing
  missing=$(smm_brew_missing) || return 1
  [ -z "$missing" ] || return 1
  unmanaged=$(smm_brew_unmanaged_casks) || return 1
  [ -z "$unmanaged" ]
}
step_brew_existing_run() { smm_brew_adopt_unmanaged && smm_brew_install_missing; }
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
# Cask token -> the app name macOS knows it by.
smm_cask_app() { case "$1" in alt-tab) echo AltTab ;; aerospace) echo AeroSpace ;; *) echo "$1" ;; esac; }
step_dedupe_run() {
  local duplicates kind name file services taps full
  duplicates=$(smm_brew_duplicates) || return 1
  file="$(smm_state_dir)/deduped"
  services="$(smm_state_dir)/deduped-services"
  taps="$(smm_state_dir)/deduped-taps"
  while IFS=' ' read -r kind name; do
    [ -n "$name" ] || continue
    # Journal before stopping anything so interruption is recoverable.
    if [ ! -f "$file" ] || ! grep -Fxq "$kind $name" "$file"; then printf '%s %s\n' "$kind" "$name" >> "$file"; fi
    case "$kind" in
      brew)
        # Third-party tap formulae need an explicit trust to be reinstalled.
        full=$(brew list --full-name --formula 2>/dev/null | grep -E "^[^/]+/[^/]+/$name\$" | head -n 1) || full=''
        if [ -n "$full" ] && ! grep -Fxqs "$name $full" "$taps"; then printf '%s %s\n' "$name" "$full" >> "$taps"; fi
        # Recovery restarts only services that were running before.
        if brew services list 2>/dev/null | awk -v name="$name" '$1 == name && $2 == "started" { found=1 } END { exit !found }' &&
          ! grep -Fxqs "$name" "$services"; then
          printf '%s\n' "$name" >> "$services"
        fi
        brew services stop "$name" || :; HOMEBREW_NO_AUTOREMOVE=1 brew uninstall "$name" || return 1 ;;
      cask)
        osascript -e 'on run argv' -e 'tell application (item 1 of argv) to quit' -e 'end run' "$(smm_cask_app "$name")" || :
        HOMEBREW_NO_AUTOREMOVE=1 brew uninstall --cask "$name" || return 1 ;;
      *) return 1 ;;
    esac
  done <<< "$duplicates"
}
smm_setup_restore_brew() {
  local file services taps kind name full failed=0
  file="$(smm_state_dir)/deduped"
  services="$(smm_state_dir)/deduped-services"
  taps="$(smm_state_dir)/deduped-taps"
  [ -s "$file" ] || return 0
  while IFS=' ' read -r kind name; do
    case "$kind" in
      brew)
        # These were installed before setup removed them. Homebrew refuses
        # formulae from untrusted taps (e.g. felixkratz/formulae/borders), so
        # trust exactly the formula that was installed, then reinstall it.
        full=$(awk -v name="$name" '$1 == name { print $2; exit }' "$taps" 2>/dev/null) || full=''
        if [ -n "$full" ]; then
          brew trust --formula "$full" || :
          brew install "$full" || { failed=1; continue; }
        else brew install "$name" || { failed=1; continue; }; fi
        if grep -Fxqs "$name" "$services"; then brew services start "$name" || failed=1; fi ;;
      cask)
        brew install --cask "$name" && open -a "$(smm_cask_app "$name")" || failed=1 ;;
      *) failed=1 ;;
    esac
  done < "$file"
  [ "$failed" -ne 0 ] || { : > "$file"; rm -f "$services" "$taps"; }
  return "$failed"
}
smm_setup_recover() {
  local file failed=0 previous=''
  export PATH="${SMM_SETUP_ORIGINAL_PATH:-$PATH}"
  file="$(smm_state_dir)/setup-generation"
  if [ -f "$file" ]; then
    previous=$(cat "$file") || return 1
    smm_rollback "$previous" || failed=1
    [ "$failed" -ne 0 ] || rm -f "$file"
  fi
  if [ -n "${SMM_TX:-}" ]; then smm_tx_restore || failed=1; fi
  smm_setup_restore_brew || failed=1
  if [ -n "$previous" ]; then smm_reload || :; fi
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
  local state prev names name target
  state=$(smm_state_dir) || return 1
  smm_use_build_tools && SMM_SKIP_PREFS=1 SMM_SKIP_AEROSPACE=1 smm_run_validate "$(smm_repo)" || return 1
  if [ -n "${SMM_TX:-}" ]; then
    # The configs step can be skipped on a fresh Mac. Journal absent targets too.
    names=$(link_names) || return 1
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      target=$(link_field "$name" target) || return 1
      smm_safe_relative "$target" && smm_tx_watch "$HOME/$target" target || return 1
    done <<< "$names"
  fi
  prev=$(smm_generation) || return 1
  printf '%s\n' "$prev" > "$state/setup-generation" || return 1
  if [ -n "${SMM_TX:-}" ]; then
    smm_tx_arm "$state/applied.hash" || return 1
    smm_setup_journal_hm_conflicts || return 1
    smm_tx_clear_targets || return 1
  fi
  if ! smm_switch; then smm_setup_recover || warn 'recovery incomplete'; return 1; fi
  # A running AeroSpace keeps its old config (e.g. its workspace list) until
  # reloaded; SketchyBar reads that list when its agent restarts below.
  smm_reload aerospace || warn 'AeroSpace did not reload its config; run aerospace reload-config'
  smm_restart_nix_agents
  smm_validate_prefs "$(smm_repo)" || return 1
  # The system is already active; an app refusing to quit (Raycast answers
  # AppleScript quit with -128) is no reason to roll it back. The prefs hash
  # isn't advanced, so the next apply relaunches it again.
  smm_prefs_relaunch || warn 'an app did not restart; quit and reopen it to apply its preferences'
  smm_run_validate "$(smm_repo)" aerospace || return 1
  smm_need_restart 'macOS menu bar and symbolic hotkey defaults' || return 1
}

# home-manager refuses to replace real files with its links (e.g. a git clone
# at ~/.config/tmux/plugins/catppuccin/tmux). Journal every conflicting target in
# the candidate generation, including ones outside the link manifest, so the
# switch moves them aside and recovery puts them back. Setup's backup keeps a copy.
smm_setup_hm_files() {
  local state build
  state=$(smm_state_dir) || return 1
  [ -f "$state/last-build" ] || return 0
  build=$(cat "$state/last-build") || return 1
  smm_nix path-info --recursive "$build" 2>/dev/null | grep -E -- '-home-manager-files$' | head -n 1
}
smm_setup_journal_hm_conflicts() {
  local files rel target backup='' managed name
  # Unknown generation contents: home-manager itself still refuses to clobber.
  files=$(smm_setup_hm_files) || files=""
  [ -n "$files" ] && [ -d "$files" ] || return 0
  # Manifest links are journaled and backed up by the configs and switch steps.
  managed=$(link_names | while IFS= read -r name; do [ -z "$name" ] || link_field "$name" target; done) || return 1
  while IFS= read -r -d '' rel; do
    rel=${rel#./}
    smm_safe_relative "$rel" || continue
    ! grep -Fxq -- "$rel" <<< "$managed" || continue
    target="$HOME/$rel"
    if [ -e "$target" ] && [ ! -L "$target" ]; then
      [ -n "$backup" ] || backup=$(smm_backup_dir) || return 1
      log "moving aside for home-manager: ~/$rel (copy in $backup)"
      mkdir -p "$backup/$(dirname "$rel")" || return 1
      [ -e "$backup/$rel" ] || cp -a "$target" "$backup/$rel" || return 1
      smm_tx_watch "$target" target || return 1
    fi
  done < <(cd "$files" && find . \( -type f -o -type l \) -print0)
}
# AeroSpace, not brew services, used to start Homebrew's SketchyBar and borders,
# so they keep running after dedupe removes them. Each allows one instance, so
# the Nix launchd agents exit and health would query the old bar and config.
smm_restart_nix_agents() {
  local pair name label pid path
  for pair in sketchybar:org.nixos.sketchybar borders:org.nixos.jankyborders; do
    name=${pair%%:*}; label=${pair#*:}
    launchctl print "gui/$UID/$label" >/dev/null 2>&1 || continue
    for pid in $(pgrep -x "$name"); do
      path=$(ps -o comm= -p "$pid") || continue
      case "$path" in /nix/store/*) ;; *) kill "$pid" 2>/dev/null || : ;; esac
    done
    launchctl kickstart -k "gui/$UID/$label" >/dev/null 2>&1 || warn "could not start $label"
  done
}
step_permissions_done() {
  smm_permission_granted aerospace && smm_permission_granted karabiner || return 1
  ! smm_app_bundle alttab >/dev/null
}
step_permissions_run() {
  smm_wait_permission aerospace || return "$?"
  smm_wait_permission karabiner || return "$?"
  # Start the Nix-installed AltTab so it can ask for, and use, its permissions.
  if smm_app_bundle alttab >/dev/null; then open -a "$(smm_app_bundle alttab)" || :; smm_wait_permission alttab; fi
}
step_signin_done() { op whoami >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; }
step_signin_run() (
  local file answer result=0 pid='' state
  trap '[ -z "$pid" ] || { kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; }' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  state=$(smm_state_dir) || return 1
  file="$state/signin-skipped"
  : > "$file"
  if [ -n "${SMM_ANSWERS:-}" ] || ! smm_has_tty; then
    if ! op whoami >/dev/null 2>&1; then
      answer=$(smm_answer signin.op 'Sign in to 1Password now?' now skip) || return "$?"
      case "$answer" in
        skip) printf '1Password not signed in (weather disabled)\n' >> "$file" ;;
        now)
          open -a '1Password' || return 1
          smm_user_wait op 'Unlock/sign in to 1Password and enable CLI integration' smm_op_ready || return "$?" ;;
        *) warn 'invalid answer signin.op (allowed: now skip)'; return 1 ;;
      esac
    fi
    if ! gh auth status >/dev/null 2>&1; then
      answer=$(smm_answer signin.gh 'Sign in to GitHub now?' now skip) || return "$?"
      case "$answer" in
        skip) printf 'GitHub not signed in (push disabled)\n' >> "$file" ;;
        now)
          # gh prints its one-time code before waiting. Prefix every line so
          # an agent can relay it; keep the login process alive while polling.
          : > "$state/gh-login.output" || return 1
          gh auth login --web > "$state/gh-login.output" 2>&1 </dev/null &
          pid=$!
          result=0
          smm_wait_github "$state/gh-login.output" || result=$?
          kill "$pid" 2>/dev/null || :; wait "$pid" 2>/dev/null || :; pid=''
          [ "$result" -eq 0 ] || return "$result" ;;
        *) warn 'invalid answer signin.gh (allowed: now skip)'; return 1 ;;
      esac
    fi
  else
    if ! op whoami >/dev/null 2>&1; then
      if smm_setup_confirm signin.op 'Sign in to 1Password now?'; then
        open -a '1Password' || return 1
        while ! op whoami >/dev/null 2>&1; do
          smm_setup_confirm user.op 'Enable 1Password CLI integration. Done (or cancel to skip)?' || break
        done
      fi
      op whoami >/dev/null 2>&1 || printf '1Password not signed in (weather disabled)\n' >> "$file"
    fi
    if ! gh auth status >/dev/null 2>&1; then
      if smm_setup_confirm signin.gh 'Sign in to GitHub now?'; then gh auth login --web || :; fi
      gh auth status >/dev/null 2>&1 || printf 'GitHub not signed in (push disabled)\n' >> "$file"
    fi
  fi
  if [ -s "$file" ]; then warn "degraded: $(cat "$file")"; fi
  return 0
)
smm_op_ready() { op whoami >/dev/null 2>&1; }
smm_wait_github() {
  local elapsed=0 limit=${SMM_WAIT_SECONDS:-600} line seen=0 count=0
  case "$limit" in ''|*[!0-9]*) warn 'invalid SMM_WAIT_SECONDS'; return 1 ;; esac
  smm_signal SMM-WAITING 'Complete GitHub web authentication' || return 1
  while :; do
    count=0
    while IFS= read -r line; do
      count=$((count + 1))
      [ "$count" -le "$seen" ] || smm_signal SMM-NEEDS "user gh: $line" || return 1
    done < "$1"
    seen=$count
    gh auth status >/dev/null 2>&1 && return 0
    [ "$elapsed" -lt "$limit" ] || break
    sleep 2; elapsed=$((elapsed + 2))
  done
  smm_signal SMM-NEEDS 'user gh: Complete GitHub web authentication, then rerun setup' || return 1
  return 3
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
  IFS= read -r -s value </dev/tty || return 1
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
        if [ -n "${SMM_ANSWERS:-}" ] || ! smm_has_tty; then
          answer=$(smm_answer "secret.$name.create" "Create missing 1Password item $vault/$item for $name?" yes no) || exit "$?"
        elif confirm "Create missing 1Password item $vault/$item for $name?"; then answer=yes;
        else answer=no; fi
        if [ "$answer" = no ]; then
          printf '%s secret not configured\n' "$name" >> "$skipped"
          continue
        fi
        if ! smm_has_tty; then
          open -a '1Password' || exit 1
          smm_user_wait "secret.$name" "Create/populate $vault/$item in 1Password, then rerun setup" '' || exit "$?"
          op item get "$item" --vault "$vault" --format json >/dev/null 2>&1 || {
            smm_signal SMM-NEEDS "user secret.$name: Create/populate $vault/$item in 1Password, then rerun setup"; exit 3;
          }
        else
        if ! op vault get "$vault" >/dev/null 2>&1; then op vault create "$vault" >/dev/null 2>&1 || exit 1; fi
        smm_setup_read_secret "$tmp/value" || exit 1
        # 1Password's item JSON template keeps the value on stdin, never argv.
        jq -n --arg title "$item" --arg field "$field" --rawfile value "$tmp/value" \
          '{title:$title,category:"SECURE_NOTE",fields:[{id:$field,label:$field,type:"CONCEALED",value:$value}]}' > "$tmp/item.json" || exit 1
        op item create - --vault "$vault" < "$tmp/item.json" >/dev/null 2>&1 || { warn "could not create $name item"; exit 1; }
        fi
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
step_health_done() { smm_health; }
step_health_run() {
  if ! smm_health; then smm_setup_recover || warn 'recovery incomplete'; return 1; fi
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
    if [ -n "${SMM_ANSWERS:-}" ] || ! smm_has_tty; then
      message=$(smm_answer commit_message 'Commit message:' text) || exit "$?"
    else
      printf 'Commit message: ' >&2
      IFS= read -r message </dev/tty || exit 1
    fi
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
  local state answer
  state=$(smm_state_dir) || return 1
  log 'Setup complete. Still manual: App Store and iCloud sign-in.'
  [ ! -s "$state/signin-skipped" ] || cat "$state/signin-skipped"
  [ ! -s "$state/secrets-skipped" ] || cat "$state/secrets-skipped"
  [ ! -s "$state/raycast-skipped" ] || cat "$state/raycast-skipped"
  if smm_restart_pending; then
    log 'Restart needed:'; cat "$state/restart-needed"
    if [ -n "${SMM_ANSWERS:-}" ] || ! smm_has_tty; then
      answer=$(smm_answer restart 'Restart now?' now later) || return "$?"
      [ "$answer" != now ] || osascript -e 'tell app "System Events" to restart'
    elif confirm 'Restart now?'; then osascript -e 'tell app "System Events" to restart'; fi
  fi
}
