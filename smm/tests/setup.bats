#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  export REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$HOME/Repos/setup-my-mac"
  make_repo "$SMM_REPO"
  mkdir -p "$SMM_REPO/manifest" "$SMM_REPO/hosts"
  echo '{}' > "$SMM_REPO/manifest/hosts.json"
  echo '[]' > "$SMM_REPO/manifest/links.json"
  echo '[]' > "$SMM_REPO/manifest/secrets.json"
  echo '[]' > "$SMM_REPO/manifest/nix-packages.json"
  echo '{"taps":[],"brews":[],"casks":[]}' > "$SMM_REPO/manifest/homebrew.json"
  cp "$REPO/hosts/template.nix" "$SMM_REPO/hosts/template.nix"
  for file in "$REPO"/smm/lib/*.sh "$REPO"/smm/cmd/*.sh; do source "$file"; done
  stub brew 0; stub op 0; stub gh 0; stub open 0
  stub aerospace 0; stub systemextensionsctl 0 'org.pqrs.Karabiner [activated enabled]'
  stub nvim 0; stub osascript 0
}
fixture_steps() {
  SETUP_STEPS=(preflight nix host preview configs brew_adopt build finish)
  for step in preflight nix host preview configs brew_adopt build finish; do
    eval "step_${step}_done() { [ -f \"\$TMP/machine-$step\" ]; }"
    eval "step_${step}_run() { echo $step >> \"\$TMP/calls.log\"; touch \"\$TMP/machine-$step\"; }"
  done
}
@test "rerun after interrupt skips real completed steps" {
  fixture_steps
  step_build_run() { warn interrupted; return 1; }
  run cmd_setup
  [ "$status" -eq 1 ]; [[ "$output" == *'setup stopped at build:'*'run smm setup again'* ]]
  step_build_run() { echo build >> "$TMP/calls.log"; touch "$TMP/machine-build"; }
  run cmd_setup; [ "$status" -eq 0 ]
  for step in preflight nix host preview configs brew_adopt; do [ "$(calls | grep -cx "$step")" -eq 1 ]; done
}
@test "done checks real state not the log" {
  fixture_steps
  run cmd_setup; [ "$status" -eq 0 ]
  rm "$SMM_STATE/setup.log"
  run cmd_setup; [ "$status" -eq 0 ]
  [ "$(calls | wc -l | tr -d ' ')" -eq 8 ]
  rm "$TMP/machine-configs"
  run cmd_setup; [ "$status" -eq 0 ]
  [ "$(calls | grep -cx configs)" -eq 2 ]
}
@test "switch failure reinstalls deduped brew packages" {
  printf 'brew sketchybar\ncask aerospace\n' > "$SMM_STATE/deduped"
  echo sketchybar > "$SMM_STATE/deduped-services"
  smm_generation() { echo 42; }; smm_run_validate() { return 0; }
  smm_switch() { return 1; }; smm_rollback() { echo rollback >> "$TMP/calls.log"; }
  run step_switch_run; [ "$status" -eq 1 ]
  calls | grep -qx 'brew install sketchybar'; calls | grep -qx 'brew install --cask aerospace'
  calls | grep -qx 'brew services start sketchybar'
}
@test "restart prompted once at end only" {
  SETUP_STEPS=(health finish)
  step_health_done() { return 1; }; step_health_run() { echo health >> "$TMP/calls.log"; }
  smm_need_restart defaults; smm_need_restart defaults
  smm_has_tty() { return 0; }
  confirm() { return 0; }
  run cmd_setup; [ "$status" -eq 0 ]
  [ "$(calls | grep -c '^osascript ')" -eq 1 ]
  [ "$(calls | grep -E '^(health|osascript )' | head -n 1)" = health ]
  [ "$(wc -l < "$SMM_STATE/restart-needed" | tr -d ' ')" -eq 1 ]
}
@test "preview flag stops before configs and writes nothing" {
  smm_migrate_preview() { echo preview; }
  step_configs_run() { echo configs >> "$TMP/calls.log"; }
  run cmd_setup --preview; [ "$status" -eq 0 ]; [ "$output" = preview ]
  ! calls | grep -qx configs
  [ ! -f "$SMM_STATE/setup.log" ]
}
@test "skipped signin is degraded not failure and status shows it" {
  stub op 1; stub gh 1
  export SMM_ANSWERS="$TMP/answers.json"
  echo '{"signin.op":"skip","signin.gh":"skip"}' > "$SMM_ANSWERS"
  SETUP_STEPS=(signin finish)
  run cmd_setup; [ "$status" -eq 0 ]; [[ "$output" == *'1Password'*'GitHub'* ]]
  run cmd_status; [ "$status" -eq 0 ]; [[ "$output" == *degraded* ]]; [[ "$output" == *1Password* ]]; [[ "$output" == *GitHub* ]]
}
@test "permission grant is checked before opening pane" {
  run smm_wait_permission aerospace; [ "$status" -eq 0 ]
  ! calls | grep -q '^open '
}
@test "noninteractive missing permission opens exact pane and returns instructions" {
  stub aerospace 1
  run smm_wait_permission aerospace; [ "$status" -eq 3 ]
  calls | grep -Fq 'Privacy_Accessibility'
  [[ "$output" == *Accessibility* ]]
}
@test "Karabiner waits on driver and input monitoring panes" {
  stub systemextensionsctl 1
  run smm_wait_permission karabiner; [ "$status" -eq 3 ]
  calls | grep -Fq 'Privacy_ListenEvent'; calls | grep -Fq 'ExtensionItems'
}
@test "same configs backed up and retained until activation" {
  echo '[{"name":"test","source":"config/test","target":".test","type":"file"}]' > "$SMM_REPO/manifest/links.json"
  mkdir "$SMM_REPO/config"; echo data > "$SMM_REPO/config/test"
  cp "$SMM_REPO/config/test" "$HOME/.test"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm fixture
  export SMM_BACKUP="$TMP/backup"
  run step_configs_run; [ "$status" -eq 0 ]
  [ "$(cat "$HOME/.test")" = data ]; [ "$(cat "$SMM_BACKUP/.test")" = data ]
}
@test "host step uses template and validates names" {
  stub scutil 0 New-Mac
  export SMM_TEST_TTY_INPUT=New-Mac
  run run_tty /bin/bash -c 'for file in "$REPO"/smm/lib/*.sh; do source "$file"; done; choose() { echo "$*" >> "$TMP/calls.log"; echo "${SMM_TEST_NIX_CHOICE:-determinate}"; }; step_host_run'; [ "$status" -eq 0 ]
  [ "$(rg -c '"New-Mac"' "$SMM_REPO/hosts/New-Mac.nix")" -eq 3 ]
  run step_host_done; [ "$status" -eq 0 ]
}
@test "nix done probes daemon and failed nix cannot install silently" {
  stub nix 1
  run step_nix_done; [ "$status" -ne 0 ]
  calls | grep -qx 'nix --extra-experimental-features nix-command flakes --version'
}
@test "lock step pins and commits flake inputs when flake.lock is missing" {
  stub nix 0
  sed_inplace '/exit 0/i\
if [ "$3 $4" = "flake lock" ]; then echo "{}" > flake.lock; fi\
' "$TMP/bin/nix"
  run step_lock_done; [ "$status" -ne 0 ]
  run step_lock_run; [ "$status" -eq 0 ]
  calls | grep -qx 'nix --extra-experimental-features nix-command flakes flake lock'
  [ "$(git -C "$SMM_REPO" log -1 --format=%s)" = 'Pin Nix inputs' ]
  run step_lock_done; [ "$status" -eq 0 ]
}
@test "lock step is done when flake.lock is already tracked" {
  echo '{}' > "$SMM_REPO/flake.lock"
  git -C "$SMM_REPO" add flake.lock; git -C "$SMM_REPO" commit -qm lock
  stub nix 0
  run step_lock_done; [ "$status" -eq 0 ]
  ! calls | grep -q 'nix --extra-experimental-features nix-command flakes flake lock'
}
@test "dedupe journals before uninstall and removes duplicates from declarations" {
  echo '["sketchybar"]' > "$SMM_REPO/manifest/nix-packages.json"
  echo '{"taps":[],"brews":["sketchybar"],"casks":[]}' > "$SMM_REPO/manifest/homebrew.json"
  smm_brew_duplicates() { echo 'brew sketchybar'; }
  stub brew 0
  sed_inplace '/exit 0/i\
if [ "$1" = uninstall ]; then grep -qx "brew sketchybar" "$SMM_STATE/deduped" || exit 99; fi\
' "$TMP/bin/brew"
  run step_dedupe_run; [ "$status" -eq 0 ]
  calls | grep -qx 'brew services stop sketchybar'
  calls | grep -qx 'brew uninstall sketchybar'
}
@test "health failure rolls back and restores duplicates" {
  echo 42 > "$SMM_STATE/setup-generation"
  echo 'brew sketchybar' > "$SMM_STATE/deduped"
  smm_health() { return 1; }
  smm_rollback() { echo "rollback $1" >> "$TMP/calls.log"; }
  run step_health_run; [ "$status" -eq 1 ]
  calls | grep -qx 'rollback 42'; calls | grep -qx 'brew install sketchybar'
}
@test "all default steps complete on an isolated degraded machine" {
  step_preflight_done() { return 0; }; step_nix_done() { return 0; }
  stub scutil 0 Test-Mac
  echo '{"Test-Mac":{"nix":"determinate"}}' > "$SMM_REPO/manifest/hosts.json"
  cp "$SMM_REPO/hosts/template.nix" "$SMM_REPO/hosts/Test-Mac.nix"
  smm_seed_host_zsh Test-Mac
  mkdir -p "$SMM_REPO/config/nvim"; echo '{}' > "$SMM_REPO/config/nvim/lazy-lock.json"
  echo '{}' > "$SMM_REPO/flake.lock"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm fixture
  stub op 1; stub gh 1; stub pgrep 0; stub sketchybar 0 '{"items":[]}'
  export SMM_ANSWERS="$TMP/answers.json"
  echo '{"continue":"yes","signin.op":"skip","signin.gh":"skip","restart":"now"}' > "$SMM_ANSWERS"
  confirm() { return 0; }
  smm_etc_entries() { echo '{}'; }
  smm_build() { mkdir -p "$TMP/build/sw/bin"; echo "$TMP/build" > "$SMM_STATE/last-build"; }
  smm_generation() { echo 42; }
  smm_switch() { smm_nix_inputs_hash > "$SMM_STATE/applied.hash"; }
  run cmd_setup
  [ "$status" -eq 0 ]; [[ "$output" == *'Setup complete'* ]]
  [ ! -f "$SMM_STATE/setup-generation" ]
  [ -f "$SMM_STATE/applied.hash" ]
  [ "$(calls | grep -c '^osascript ')" -eq 1 ]
}
@test "known duplicate is excluded from adopt or remove until replacement builds" {
  smm_brew_duplicates() { echo 'brew sketchybar'; }
  smm_brew_undeclared() { echo 'brew sketchybar'; }
  smm_brew_interactive() { return 0; }
  choose() { echo remove; }
  run step_brew_adopt_run; [ "$status" -eq 0 ]
  ! calls | grep -q 'brew uninstall'
}
@test "setup creates a missing 1Password item without putting the secret in argv" {
  echo '[{"name":"weather","op_ref":"op://smm/weather/env","target":"weather.env.sh"}]' > "$SMM_REPO/manifest/secrets.json"
  stub op 0
  sed_inplace '/exit 0/i\
case "$*" in\
  "item get weather --vault smm --format json") [ -f "$TMP/created" ] || exit 1 ;;\
  "item create - --vault smm") cat > "$TMP/item.json"; touch "$TMP/created" ;;\
  "read op://smm/weather/env") [ -f "$TMP/created" ] || exit 1; echo "weather_key=testvalue" ;;\
esac\
' "$TMP/bin/op"
  smm_has_tty() { return 0; }
  confirm() { return 0; }
  smm_setup_read_secret() { printf 'weather_key=testvalue\n' > "$1"; }
  run step_secrets_run; [ "$status" -eq 0 ]
  [ "$(cat "$HOME/weather.env.sh")" = weather_key=testvalue ]
  jq -e '.fields[0].value == "weather_key=testvalue\n"' "$TMP/item.json"
  ! calls | grep -q testvalue
}
@test "new host is tracked before a Git flake build can discover it" {
  stub scutil 0 New-Mac
  export SMM_TEST_TTY_INPUT=New-Mac
  run run_tty /bin/bash -c 'for file in "$REPO"/smm/lib/*.sh; do source "$file"; done; choose() { echo "$*" >> "$TMP/calls.log"; echo "${SMM_TEST_NIX_CHOICE:-determinate}"; }; step_host_run'; [ "$status" -eq 0 ]
  git -C "$SMM_REPO" ls-files --error-unmatch hosts/New-Mac.nix
  [ "$(git -C "$SMM_REPO" show --format= --name-only HEAD)" = hosts/New-Mac.nix ]
}

@test "new host records its implementation before Nix setup" {
  stub scutil 0 New-Mac
  export SMM_TEST_TTY_INPUT=New-Mac SMM_TEST_NIX_CHOICE=lix
  run run_tty /bin/bash -c 'for file in "$REPO"/smm/lib/*.sh; do source "$file"; done; choose() { echo "$*" >> "$TMP/calls.log"; echo "$SMM_TEST_NIX_CHOICE"; }; step_host_run'
  [ "$status" -eq 0 ]
  jq -e '. == {"New-Mac":{"nix":"lix"}}' "$SMM_REPO/manifest/hosts.json"
  calls | grep -qx 'Choose Nix implementation determinate lix'
  smm_setup_steps
  [[ " ${SETUP_STEPS[*]} " == *' host nix '* ]]
  run step_host_done; [ "$status" -eq 0 ]
}
@test "known host keeps its implementation without asking again" {
  stub scutil 0 New-Mac
  export SMM_TEST_TTY_INPUT=New-Mac
  echo '{"New-Mac":{"nix":"lix","other":"preserved"}}' > "$SMM_REPO/manifest/hosts.json"
  run run_tty /bin/bash -c 'for file in "$REPO"/smm/lib/*.sh; do source "$file"; done; choose() { exit 99; }; step_host_run'
  [ "$status" -eq 0 ]
  jq -e '. == {"New-Mac":{"nix":"lix","other":"preserved"}}' "$SMM_REPO/manifest/hosts.json"
  echo '{}' > "$SMM_REPO/manifest/hosts.json"
  run step_host_done; [ "$status" -ne 0 ]
}

@test "cancelled or invalid implementation choices do not register a host" {
  stub scutil 0 New-Mac
  export SMM_TEST_TTY_INPUT=New-Mac
  for SMM_TEST_NIX_CHOICE in cancel invalid; do
    export SMM_TEST_NIX_CHOICE
    run run_tty /bin/bash -c 'for file in "$REPO"/smm/lib/*.sh; do source "$file"; done; choose() { [ "$SMM_TEST_NIX_CHOICE" != cancel ] || return 1; echo "$SMM_TEST_NIX_CHOICE"; }; step_host_run'
    [ "$status" -ne 0 ]
    jq -e '. == {}' "$SMM_REPO/manifest/hosts.json"
    [ ! -f "$SMM_REPO/hosts/New-Mac.nix" ]
  done
}
@test "setup preinstalls missing formula and sudo pkg cask as user before build and switch" {
  stub_pkg_brew
  smm_has_tty() { return 1; }
  SETUP_STEPS=(brew_existing build switch)
  step_build_done() { return 1; }
  step_build_run() { [ -f "$TMP/brew-installed" ] && echo built >> "$TMP/calls.log"; }
  step_switch_done() { return 1; }
  step_switch_run() { [ -f "$TMP/brew-installed" ] && echo switched >> "$TMP/calls.log"; }
  run cmd_setup
  [ "$status" -eq 0 ]
  [ "$(cat "$TMP/brew-askpass")" = "$SMM_TEST_ASKPASS" ]
  calls | grep -qx "brew bundle install --file=$SMM_STATE/Brewfile --no-upgrade"
  [ "$(calls | awk '/^brew bundle install/ {print NR}')" -lt "$(calls | awk '/^built$/ {print NR}')" ]
  run step_brew_existing_done
  [ "$status" -eq 0 ]
  : > "$TMP/calls.log"
  run cmd_setup
  [ "$status" -eq 0 ]
  ! calls | grep -q '^brew bundle install '
}
@test "failed package preinstall stops setup before build and switch" {
  stub_pkg_brew; touch "$TMP/brew-fail"
  smm_has_tty() { return 1; }
  SETUP_STEPS=(brew_existing build)
  step_build_done() { return 1; }
  step_build_run() { echo built >> "$TMP/calls.log"; }
  run cmd_setup
  [ "$status" -ne 0 ]
  ! calls | grep -qx built
}
@test "duplicates keep a formula another installed formula depends on" {
  echo '["ripgrep","fd"]' > "$SMM_REPO/manifest/nix-packages.json"
  stub brew 0
  sed_inplace '/exit 0/i\
case "$*" in\
  "list --formula") printf "ripgrep\\nfd\\n" ;;\
  "uses --installed ripgrep") echo opencode-v2 ;;\
esac\
' "$TMP/bin/brew"
  run smm_brew_duplicates; [ "$status" -eq 0 ]
  [ "$output" = 'brew fd' ]
}
@test "dedupe records running services and recovery restarts only those, trusting prior taps" {
  echo '["sketchybar","fd"]' > "$SMM_REPO/manifest/nix-packages.json"
  smm_brew_duplicates() { printf 'brew sketchybar\nbrew fd\n'; }
  stub brew 0
  sed_inplace '/exit 0/i\
case "$*" in\
  "services list") printf "Name Status User File\\nsketchybar started me x\\nfd none\\n" ;;\
  "list --full-name --formula") printf "fd\\nfelixkratz/formulae/sketchybar\\n" ;;\
  "install felixkratz/formulae/sketchybar") grep -qx "brew trust --formula felixkratz/formulae/sketchybar" "$TMP/calls.log" || exit 97 ;;\
  "services start fd") exit 1 ;;\
esac\
' "$TMP/bin/brew"
  run step_dedupe_run; [ "$status" -eq 0 ]
  [ "$(cat "$SMM_STATE/deduped-services")" = sketchybar ]
  [ "$(cat "$SMM_STATE/deduped-taps")" = 'sketchybar felixkratz/formulae/sketchybar' ]
  run smm_setup_restore_brew; [ "$status" -eq 0 ]
  calls | grep -qx 'brew install felixkratz/formulae/sketchybar'; calls | grep -qx 'brew install fd'
  ! calls | grep -qx 'brew trust --formula fd' || return 1
  calls | grep -qx 'brew services start sketchybar'
  ! calls | grep -qx 'brew services start fd' || return 1
  [ ! -s "$SMM_STATE/deduped" ]; [ ! -e "$SMM_STATE/deduped-services" ]; [ ! -e "$SMM_STATE/deduped-taps" ]
}
@test "switch keeps the activated system when an app refuses to restart" {
  smm_use_build_tools() { :; }; smm_run_validate() { return 0; }
  smm_switch() { :; }; smm_validate_prefs() { :; }
  smm_prefs_relaunch() { echo 'execution error: Raycast got an error: User canceled. (-128)' >&2; return 1; }
  smm_setup_recover() { echo recover >> "$TMP/calls.log"; }
  run step_switch_run; [ "$status" -eq 0 ]
  [[ "$output" == *'quit and reopen it'* ]] || return 1
  ! calls | grep -qx recover || return 1
}
@test "after switching, stale non-Nix sketchybar and borders are replaced by the Nix agents" {
  stub launchctl 0
  stub pgrep 0
  sed_inplace '/exit 0/i\
case "$*" in "-x sketchybar") echo 101 ;; "-x borders") printf "202\\n303\\n" ;; esac\
' "$TMP/bin/pgrep"
  stub ps 0
  sed_inplace '/exit 0/i\
case "$*" in *101*) echo sketchybar ;; *202*) echo /opt/homebrew/bin/borders ;; *303*) echo /nix/store/x-jankyborders/bin/borders ;; esac\
' "$TMP/bin/ps"
  kill() { echo "kill $*" >> "$TMP/calls.log"; }
  smm_restart_nix_agents
  calls | grep -qx 'kill 101'; calls | grep -qx 'kill 202'
  ! calls | grep -qx 'kill 303' || return 1
  calls | grep -q "launchctl kickstart -k gui/$UID/org.nixos.sketchybar"
  calls | grep -q "launchctl kickstart -k gui/$UID/org.nixos.jankyborders"
}
@test "switch reloads AeroSpace before restarting the Nix agents" {
  smm_use_build_tools() { :; }; smm_run_validate() { return 0; }
  smm_switch() { :; }; smm_validate_prefs() { :; }; smm_prefs_relaunch() { :; }
  smm_reload() { echo "reload $*" >> "$TMP/calls.log"; }
  smm_restart_nix_agents() { echo agents >> "$TMP/calls.log"; }
  run step_switch_run; [ "$status" -eq 0 ]
  [ "$(grep -nx 'reload aerospace' "$TMP/calls.log" | cut -d: -f1)" -lt "$(grep -nx agents "$TMP/calls.log" | cut -d: -f1)" ]
}
@test "home-manager conflicts outside the link manifest are moved aside and restored on recovery" {
  echo '[{"name":"zsh","source":"config/zshrc","target":".zshrc","type":"file"}]' > "$SMM_REPO/manifest/links.json"
  mkdir -p "$TMP/hm/.config/tmux/plugins/catppuccin" "$TMP/hm/.config/kitty"
  ln -s /nix/store/x-catppuccin "$TMP/hm/.config/tmux/plugins/catppuccin/tmux"
  ln -s /nix/store/x-kitty "$TMP/hm/.config/kitty/kitty.conf"
  ln -s /nix/store/x-zshrc "$TMP/hm/.zshrc"
  smm_setup_hm_files() { echo "$TMP/hm"; }
  mkdir -p "$HOME/.config/tmux/plugins/catppuccin/tmux"; echo clone > "$HOME/.config/tmux/plugins/catppuccin/tmux/README"
  echo mine > "$HOME/.zshrc"
  export SMM_BACKUP="$TMP/backup"
  smm_tx_begin setup
  run smm_setup_journal_hm_conflicts; [ "$status" -eq 0 ]
  [[ "$output" == *'.config/tmux/plugins/catppuccin/tmux'* ]] || return 1
  [[ "$output" != *'.zshrc'* ]] || return 1
  [ "$(cat "$TMP/backup/.config/tmux/plugins/catppuccin/tmux/README")" = clone ]
  smm_tx_clear_targets
  [ ! -e "$HOME/.config/tmux/plugins/catppuccin/tmux" ]; [ "$(cat "$HOME/.zshrc")" = mine ]
  smm_tx_restore
  [ "$(cat "$HOME/.config/tmux/plugins/catppuccin/tmux/README")" = clone ]
}
