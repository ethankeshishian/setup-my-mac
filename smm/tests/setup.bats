#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  export REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$HOME/Repos/setup-my-mac"
  make_repo "$SMM_REPO"
  mkdir -p "$SMM_REPO/manifest" "$SMM_REPO/hosts"
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
  run smm_wait_permission aerospace; [ "$status" -eq 1 ]
  calls | grep -Fq 'Privacy_Accessibility'
  [[ "$output" == *Accessibility* ]]
}
@test "Karabiner waits on driver and input monitoring panes" {
  stub systemextensionsctl 1
  run smm_wait_permission karabiner; [ "$status" -eq 1 ]
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
  run run_tty /bin/bash -c 'for file in "$REPO"/smm/lib/*.sh; do source "$file"; done; step_host_run'; [ "$status" -eq 0 ]
  [ "$(rg -c '"New-Mac"' "$SMM_REPO/hosts/New-Mac.nix")" -eq 3 ]
  run step_host_done; [ "$status" -eq 0 ]
}
@test "nix done probes daemon and failed nix cannot install silently" {
  stub nix 1
  run step_nix_done; [ "$status" -ne 0 ]
  calls | grep -qx 'nix --version'
}
@test "dedupe journals before uninstall and removes duplicates from declarations" {
  echo '["sketchybar"]' > "$SMM_REPO/manifest/nix-packages.json"
  echo '{"taps":[],"brews":["sketchybar"],"casks":[]}' > "$SMM_REPO/manifest/homebrew.json"
  smm_brew_duplicates() { echo 'brew sketchybar'; }
  stub brew 0
  sed -i '' '/exit 0/i\
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
  cp "$SMM_REPO/hosts/template.nix" "$SMM_REPO/hosts/Test-Mac.nix"
  mkdir -p "$SMM_REPO/config/nvim"; echo '{}' > "$SMM_REPO/config/nvim/lazy-lock.json"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm fixture
  stub op 1; stub gh 1; stub pgrep 0; stub sketchybar 0 '{"items":[]}'
  confirm() { return 0; }
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
  sed -i '' '/exit 0/i\
case "$*" in\
  "item get weather --vault smm --format json") [ -f "$TMP/created" ] || exit 1 ;;\
  "item create - --vault smm") cat > "$TMP/item.json"; touch "$TMP/created" ;;\
  "read op://smm/weather/env") [ -f "$TMP/created" ] || exit 1; echo "weather_key=testvalue" ;;\
esac\
' "$TMP/bin/op"
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
  run run_tty /bin/bash -c 'for file in "$REPO"/smm/lib/*.sh; do source "$file"; done; step_host_run'; [ "$status" -eq 0 ]
  git -C "$SMM_REPO" ls-files --error-unmatch hosts/New-Mac.nix
  [ "$(git -C "$SMM_REPO" show --format= --name-only HEAD)" = hosts/New-Mac.nix ]
}
