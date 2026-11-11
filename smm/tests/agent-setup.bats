#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  export REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo" SMM_HOST=Test-Mac SMM_ETC_ROOT="$TMP/etc"
  mkdir -p "$SMM_REPO/manifest" "$SMM_REPO/hosts" "$SMM_ETC_ROOT"
  echo '[]' > "$SMM_REPO/manifest/links.json"; echo '[]' > "$SMM_REPO/manifest/secrets.json"
  echo '{}' > "$SMM_REPO/manifest/hosts.json"
  echo '[]' > "$SMM_REPO/manifest/nix-packages.json"
  echo '{"taps":[],"brews":[],"casks":[]}' > "$SMM_REPO/manifest/homebrew.json"
  for file in "$REPO"/smm/lib/*.sh "$REPO"/smm/cmd/*.sh; do source "$file"; done
  smm_has_tty() { return 1; }
  smm_etc_entries() { echo '{}'; }
  smm_brew_undeclared() { echo 'brew direnv'; }
  smm_brew_duplicates() { :; }
  smm_brew_unmanaged_casks() { :; }
  export SMM_ANSWERS="$TMP/answers.json" SMM_WAIT_SECONDS=0
  echo '{}' > "$SMM_ANSWERS"
}
@test "answers handle choice confirm and text and reject invalid values" {
  echo '{"config.zsh":"local","continue":"yes","commit_message":"My migration"}' > "$SMM_ANSWERS"
  run smm_answer config.zsh 'Config?' repo local; [ "$status" -eq 0 ]; [ "$output" = local ]
  run smm_setup_confirm continue 'Continue?'; [ "$status" -eq 0 ]
  run smm_answer commit_message 'Commit message:' text; [ "$status" -eq 0 ]; [ "$output" = 'My migration' ]
  echo '{"config.zsh":"remove"}' > "$SMM_ANSWERS"
  run smm_answer config.zsh 'Config?' repo local; [ "$status" -eq 1 ]; [[ "$output" == *invalid* ]]
}
@test "missing answer exits 3 logs a machine readable need and rerun consumes it" {
  run smm_answer config.zsh 'Which config?' repo local
  [ "$status" -eq 3 ]; [ "$output" = 'SMM-NEEDS: answer config.zsh: Which config? (allowed: repo local)' ]
  grep -Fx "$output" "$SMM_STATE/needs.log"
  echo '{"config.zsh":"repo"}' > "$SMM_ANSWERS"
  run smm_answer config.zsh 'Which config?' repo local; [ "$status" -eq 0 ]
}
@test "setup propagates exit 3 and resumes real completed steps" {
  SETUP_STEPS=(answer)
  step_answer_done() { [ -f "$TMP/completed" ]; }
  step_answer_run() { smm_answer continue 'Continue?' yes no >/dev/null || return "$?"; touch "$TMP/completed"; }
  run cmd_setup --answers "$SMM_ANSWERS"; [ "$status" -eq 3 ]; [ ! -f "$TMP/completed" ]
  echo '{"continue":"yes"}' > "$SMM_ANSWERS"
  run cmd_setup --answers "$SMM_ANSWERS"; [ "$status" -eq 0 ]; [ -f "$TMP/completed" ]
}
@test "a pause after activation keeps the switch and resumes the same journal" {
  SETUP_STEPS=(switched wait)
  step_switched_done() { [ -f "$TMP/switched" ]; }
  step_switched_run() { echo 7 > "$SMM_STATE/setup-generation"; smm_tx_watch "$HOME/.zshrc" target; touch "$TMP/switched"; }
  step_wait_done() { [ -f "$TMP/waited" ]; }
  step_wait_run() { smm_answer continue 'Continue?' yes no >/dev/null || return "$?"; touch "$TMP/waited"; }
  smm_setup_recover() { echo recover >> "$TMP/calls.log"; }
  smm_finalize_apply() { :; }
  run cmd_setup --answers "$SMM_ANSWERS"; [ "$status" -eq 3 ]
  [[ "$output" == *'setup paused at wait'* ]] || return 1
  ! calls | grep -qx recover || return 1
  [ -f "$SMM_STATE/setup.transaction/paused" ]
  [ "$(cat "$SMM_STATE/setup-generation")" = 7 ]
  echo '{"continue":"yes"}' > "$SMM_ANSWERS"
  run cmd_setup --answers "$SMM_ANSWERS"; [ "$status" -eq 0 ]
  [ -f "$TMP/waited" ]; [ ! -e "$SMM_STATE/setup.transaction" ]
  ! calls | grep -qx recover || return 1
}
@test "a real failure still recovers" {
  SETUP_STEPS=(broken)
  step_broken_done() { return 1; }; step_broken_run() { return 1; }
  smm_setup_recover() { echo recover >> "$TMP/calls.log"; }
  run cmd_setup --answers "$SMM_ANSWERS"; [ "$status" -eq 1 ]
  calls | grep -qx recover; [ ! -e "$SMM_STATE/setup.transaction" ]
}
@test "plan inventories questions with safe defaults without changing repo or calling mutations" {
  echo '[{"name":"old"},{"name":"mine"},{"name":"both"}]' > "$SMM_REPO/manifest/links.json"
  smm_migrate_status() { case "$1" in old) echo repo-newer ;; mine) echo local-newer ;; both) echo both-changed ;; esac; }
  smm_brew_unmanaged_casks() { printf 'arc\tArc.app\nother\tOther.app\n'; }
  smm_cask_versions_match() { [ "$1" = arc ]; }
  echo 'echo work' > "$SMM_ETC_ROOT/zshenv"
  smm_etc_entries() { echo '{"zshenv":{"enable":true,"target":"zshenv","knownSha256Hashes":[]}}'; }
  run cmd_setup --plan "$TMP/plan.json"; [ "$status" -eq 0 ]
  jq -e '.questions | all(.[]; has("key") and has("question") and has("allowed") and has("recommended") and has("value"))' "$TMP/plan.json"
  jq -e '[.questions[] | select(.key == "config.old")][0].value == "repo"' "$TMP/plan.json"
  jq -e '[.questions[] | select(.key == "config.mine" or .key == "config.both" or .key == "etc.zshenv") | .value] == [null,null,null]' "$TMP/plan.json"
  jq -e '[.questions[] | select(.key == "brew.brew.direnv")][0].value == "skip"' "$TMP/plan.json"
  jq -e '[.questions[] | select(.key == "unmanaged.arc")][0].value == "adopt"' "$TMP/plan.json"
  jq -e '[.questions[] | select(.key == "unmanaged.other")][0].value == null' "$TMP/plan.json"
  jq -e '[.questions[] | select(.key == "restart")][0].value == "later"' "$TMP/plan.json"
  ! calls | grep -E ' (install|uninstall|switch|login|repair|add|commit|push)( |$)'
  [ ! -f "$SMM_STATE/setup.log" ]; [ ! -d "$SMM_REPO/hosts/etc" ]
}
@test "generated plans are consumed directly and default plan is on Desktop" {
  make_repo "$SMM_REPO"
  stub nix 0 '{}'; stub brew 0; stub op 0; stub gh 0; stub aerospace 0
  run "$REPO/smm/bin/smm" setup --plan
  [ "$status" -eq 0 ]; [ -f "$HOME/Desktop/smm-answers.json" ]
  export SMM_ANSWERS="$HOME/Desktop/smm-answers.json"
  run smm_answer restart 'Restart?' now later; [ "$status" -eq 0 ]; [ "$output" = later ]
}
@test "brew never removes a package without an explicit valid answer" {
  run smm_brew_resolve; [ "$status" -eq 3 ]; ! calls | grep -q uninstall
  echo '{"brew.brew.direnv":"skip"}' > "$SMM_ANSWERS"
  run smm_brew_resolve; [ "$status" -eq 0 ]; ! calls | grep -q uninstall
  stub brew 0
  echo '{"brew.brew.direnv":"remove"}' > "$SMM_ANSWERS"
  run smm_brew_resolve; [ "$status" -eq 0 ]; calls | grep -qx 'brew uninstall direnv'
}
@test "sudo without tty uses askpass without reading a password" {
  stub sudo 0
  run smm_sudo echo hello; [ "$status" -eq 0 ]; calls | grep -qx 'sudo -A echo hello'
  [ -x "$REPO/smm/libexec/askpass" ]
  rg -F 'hidden answer' "$REPO/smm/libexec/askpass"
  rg -F 'smm needs your Mac password' "$REPO/smm/libexec/askpass"
}
@test "undetectable permission needs user acknowledgement and logs both markers" {
  stub open 0
  run smm_wait_permission alttab; [ "$status" -eq 3 ]
  [[ "$output" == *'SMM-NEEDS: user alttab:'* ]]
  grep -q '^SMM-WAITING:' "$SMM_STATE/needs.log"
  echo '{"user.alttab":"done"}' > "$SMM_ANSWERS"
  run smm_wait_permission alttab; [ "$status" -eq 0 ]
}
@test "detectable permissions poll until grant or a bounded user need" {
  stub open 0; stub aerospace 1
  run smm_wait_permission aerospace; [ "$status" -eq 3 ]
  [[ "$output" == *'SMM-NEEDS: user aerospace:'* ]]
  stub aerospace 0; run smm_wait_permission aerospace; [ "$status" -eq 0 ]
}
@test "config answers are consumed before backing up or importing" {
  mkdir -p "$SMM_REPO/config"; echo repo > "$SMM_REPO/config/test"; echo local > "$HOME/.test"
  echo '[{"name":"test","source":"config/test","target":".test","type":"file"}]' > "$SMM_REPO/manifest/links.json"
  smm_migrate_status() { echo local-newer; }
  echo '{"config.test":"local"}' > "$SMM_ANSWERS"
  run smm_migrate_resolve test; [ "$status" -eq 0 ]; [ "$(cat "$SMM_REPO/config/test")" = local ]
  [ "$(cat "$HOME/.test")" = local ]
}
@test "unmanaged app requires an explicit adoption or replacement answer" {
  smm_brew_unmanaged_casks() { printf 'arc\tArc.app\n'; }
  stub brew 0
  run smm_brew_adopt_unmanaged; [ "$status" -eq 3 ]; ! calls | grep -q 'install --cask'
  echo '{"unmanaged.arc":"adopt"}' > "$SMM_ANSWERS"
  run smm_brew_adopt_unmanaged; [ "$status" -eq 0 ]; calls | grep -qx 'brew install --cask --adopt arc'
  echo '{"unmanaged.arc":"replace"}' > "$SMM_ANSWERS"
  run smm_brew_adopt_unmanaged; [ "$status" -eq 0 ]; calls | grep -qx 'brew install --cask --force arc'
}
@test "signin opens 1Password waits and resumes without trusting a claimed grant" {
  stub op 1; stub open 0
  echo '{"signin.op":"now","user.op":"done"}' > "$SMM_ANSWERS"
  run step_signin_run; [ "$status" -eq 3 ]; [[ "$output" == *'SMM-NEEDS: user op:'* ]]
  calls | grep -qx 'open -a 1Password'
  stub op 0; stub gh 0
  run step_signin_run; [ "$status" -eq 0 ]
}
@test "restart answer later never triggers restart and now does" {
  smm_need_restart test
  echo '{"restart":"later"}' > "$SMM_ANSWERS"
  run step_finish_run; [ "$status" -eq 0 ]; ! calls | grep -q '^osascript '
  stub osascript 0; echo '{"restart":"now"}' > "$SMM_ANSWERS"
  run step_finish_run; [ "$status" -eq 0 ]; calls | grep -q '^osascript '
}
@test "installer internal sudo uses private askpass shim" {
  stub sudo 0
  cat > "$TMP/installer" <<'INSTALLER'
#!/usr/bin/env bash
sudo echo installer
printf '%s\n' "$SUDO_ASKPASS" > "$TMP/askpass-path"
INSTALLER
  run smm_installer_run "$TMP/installer" install
  [ "$status" -eq 0 ]; calls | grep -qx 'sudo -A echo installer'
  [ "$(cat "$TMP/askpass-path")" = "$(cd -P "$REPO" && pwd)/smm/libexec/askpass" ]
}
@test "invalid secret confirmation is a hard error and never fetches a value" {
  echo '[{"name":"weather","op_ref":"op://smm/weather/env","target":"weather.env.sh"}]' > "$SMM_REPO/manifest/secrets.json"
  stub op 0
  sed_inplace '/exit 0/i\
[ "$1 $2" != "item get" ] || exit 1\
' "$TMP/bin/op"
  echo '{"secret.weather.create":"invalid"}' > "$SMM_ANSWERS"
  run step_secrets_run; [ "$status" -eq 1 ]; [[ "$output" == *invalid* ]]
  ! calls | grep -q 'item create'
}
@test "setup Nix snapshot includes generated modules and excludes ignored secrets" {
  make_repo "$SMM_REPO"
  mkdir -p "$SMM_REPO/hosts/etc"
  echo '{}' > "$SMM_REPO/flake.nix"
  echo '{}' > "$SMM_REPO/hosts/etc/Test-Mac.nix"
  echo secret.env > "$SMM_REPO/.gitignore"; echo private > "$SMM_REPO/secret.env"
  export SMM_AGENT_SETUP=1
  run smm_flake_ref; [ "$status" -eq 0 ]
  snapshot=${output#path:}
  [ -f "$snapshot/hosts/etc/Test-Mac.nix" ]; [ -f "$snapshot/flake.nix" ]
  [ ! -e "$snapshot/secret.env" ]; [ ! -e "$snapshot/.git" ]
}
@test "new host prompts consume keyed names and implementation without tty" {
  make_repo "$SMM_REPO"
  cp "$REPO/hosts/template.nix" "$SMM_REPO/hosts/template.nix"
  echo '{"host.name":"New-Mac","host.nix":"lix"}' > "$SMM_ANSWERS"
  run step_host_run; [ "$status" -eq 0 ]
  [ -f "$SMM_REPO/hosts/New-Mac.nix" ]
  jq -e '."New-Mac".nix == "lix"' "$SMM_REPO/manifest/hosts.json"
}
@test "setup commit consumes its message answer and does not prompt" {
  make_repo "$SMM_REPO"
  echo change > "$SMM_REPO/fixture"
  echo '{"commit_message":"Migrate Test-Mac to smm"}' > "$SMM_ANSWERS"
  stub gh 1; smm_run_validate() { return 0; }
  run step_commit_run; [ "$status" -eq 0 ]
  [ "$(git -C "$SMM_REPO" log -1 --format=%s)" = 'Migrate Test-Mac to smm' ]
}
@test "gh web login surfaces its one-time code and bounded user action" {
  stub op 0; stub gh 0
  sed_inplace '/exit 0/i\
case "$*" in\
  "auth status") exit 1 ;;\
  "auth login --web") echo "First copy your one-time code: ABCD-EFGH"; exit 0 ;;\
esac\
' "$TMP/bin/gh"
  echo '{"signin.gh":"now"}' > "$SMM_ANSWERS"
  export SMM_WAIT_SECONDS=1
  run step_signin_run; [ "$status" -eq 3 ]
  calls | grep -qx 'gh auth login --web'
  [[ "$output" == *'SMM-NEEDS: user gh: First copy your one-time code: ABCD-EFGH'* ]]
  grep -Fq 'ABCD-EFGH' "$SMM_STATE/needs.log"
}

@test "signed out plan defers secret inventory until sign-in" {
  echo '[{"name":"weather","op_ref":"op://smm/weather/env","target":"weather.env.sh"}]' > "$SMM_REPO/manifest/secrets.json"
  stub op 1
  run cmd_setup --plan "$TMP/plan.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'checked after 1Password sign-in'* ]] || return 1
  jq -e '[.questions[] | select(.key | startswith("secret."))] == []' "$TMP/plan.json"
  ! calls | grep -q '^op item get '
}
@test "signed in plan asks to create a missing secret item" {
  echo '[{"name":"weather","op_ref":"op://smm/weather/env","target":"weather.env.sh"}]' > "$SMM_REPO/manifest/secrets.json"
  stub op 0
  sed_inplace '/exit 0/i\
[ "$1 $2" != "item get" ] || exit 1\
' "$TMP/bin/op"
  run cmd_setup --plan "$TMP/plan.json"
  [ "$status" -eq 0 ]
  jq -e 'any(.questions[]; .key == "secret.weather.create")' "$TMP/plan.json"
}
@test "plan lists accepted etc entries without asking again and review includes them" {
  echo 'export WORK=preserve' > "$SMM_ETC_ROOT/zshenv"
  smm_etc_entries() { echo '{"zshenv":{"enable":true,"target":"zshenv","knownSha256Hashes":[]}}'; }
  echo '{"etc.zshenv":"accept"}' > "$SMM_ANSWERS"
  step_build_run() { :; }
  step_etc_run
  run cmd_setup --plan "$TMP/plan.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'already accepted in hosts/etc/Test-Mac.nix: zshenv'* ]] || return 1
  jq -e 'all(.questions[]; .key != "etc.zshenv")' "$TMP/plan.json"
  before=$(shasum "$SMM_REPO/hosts/etc/Test-Mac.nix" "$SMM_ETC_ROOT/zshenv")
  run cmd_etc review
  [ "$status" -eq 0 ]
  [[ "$output" == *KEEP*WORK=preserve* ]] || return 1
  [ "$before" = "$(shasum "$SMM_REPO/hosts/etc/Test-Mac.nix" "$SMM_ETC_ROOT/zshenv")" ]
}
@test "plan and preview list missing declared Homebrew packages with password notice" {
  stub brew 0
  echo '{"taps":[],"brews":["tpm"],"casks":["logi-options+"]}' > "$SMM_REPO/manifest/homebrew.json"
  run cmd_setup --plan "$TMP/plan.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'brew tpm'*'cask logi-options+'*'password dialog may appear'* ]] || return 1
  run cmd_setup --preview
  [ "$status" -eq 0 ]
  [[ "$output" == *'brew tpm'*'cask logi-options+'*'password dialog may appear'* ]] || return 1
  ! calls | grep -q '^brew bundle install '
}
@test "plan pre-fills adoption for auto-updating unmanaged casks with different versions" {
  smm_brew_unmanaged_casks() { printf 'arc\tArc.app\n'; }
  stub brew 0 '{"casks":[{"version":"2.9","auto_updates":true}]}'
  stub plutil 0 2.1
  run cmd_setup --plan "$TMP/plan.json"
  [ "$status" -eq 0 ]
  jq -e '.questions[] | select(.key == "unmanaged.arc") | .value == "adopt" and (.allowed | index("replace") != null)' "$TMP/plan.json"
}
@test "plan asks about auto-updating unmanaged casks a major version apart" {
  smm_brew_unmanaged_casks() { printf 'mos\tMos.app\n'; }
  stub brew 0 '{"casks":[{"version":"4.2.1","auto_updates":true}]}'
  stub plutil 0 3.4.1
  run cmd_setup --plan "$TMP/plan.json"
  [ "$status" -eq 0 ]
  jq -e '.questions[] | select(.key == "unmanaged.mos") | .value == null' "$TMP/plan.json"
}
@test "apps installed outside Homebrew are adopted, not listed as fresh installs" {
  stub brew 0
  smm_brew_unmanaged_casks() { printf 'arc\tArc.app\n'; }
  echo '{"taps":[],"brews":[],"casks":["arc","logi-options+"]}' > "$SMM_REPO/manifest/homebrew.json"
  run smm_brew_missing
  [ "$status" -eq 0 ]
  [ "$output" = 'cask logi-options+' ]
}
@test "plan lists accepted entries after activation links etc into static" {
  echo 'export WORK=preserve' > "$SMM_ETC_ROOT/zshenv"
  smm_etc_entries() { echo '{"zshenv":{"enable":true,"target":"zshenv","knownSha256Hashes":[]}}'; }
  echo '{"etc.zshenv":"accept"}' > "$SMM_ANSWERS"
  step_build_run() { :; }
  step_etc_run
  mkdir "$SMM_ETC_ROOT/static"
  mv "$SMM_ETC_ROOT/zshenv" "$SMM_ETC_ROOT/static/zshenv"
  ln -s static/zshenv "$SMM_ETC_ROOT/zshenv"
  run cmd_setup --plan "$TMP/plan.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'already accepted in hosts/etc/Test-Mac.nix: zshenv'* ]] || return 1
  jq -e 'all(.questions[]; .key != "etc.zshenv")' "$TMP/plan.json"
}
