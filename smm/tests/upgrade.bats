#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo"
  make_repo "$SMM_REPO"
  mkdir -p "$SMM_REPO/config/nvim" "$SMM_REPO/manifest"
  printf '{"nodes":{"foo":{"locked":{"rev":"old"}}}}\n' > "$SMM_REPO/flake.lock"
  printf '{"plugin":{"commit":"old"}}\n' > "$SMM_REPO/config/nvim/lazy-lock.json"
  git -C "$SMM_REPO" add -A
  git -C "$SMM_REPO" commit -qm baseline
  for lib in "$REPO"/smm/lib/*.sh; do source "$lib"; done
  [ ! -f "$REPO/smm/cmd/upgrade.sh" ] || source "$REPO/smm/cmd/upgrade.sh"
  stub nix 0
  sed_inplace '/exit 0/i\
printf '\''{"nodes":{"foo":{"locked":{"rev":"new"}}}}\\n'\'' > "$SMM_REPO/flake.lock"\
' "$TMP/bin/nix"
  stub nvim 0
  stub brew 0 '{"casks":[{"name":"example","current_version":"1","installed_versions":["0"]}]}'
  smm_generation() { echo 42; }
  smm_build() { echo build >> "$TMP/calls.log"; }
  smm_switch() { echo switch >> "$TMP/calls.log"; }
  smm_rollback() { echo "rollback $1" >> "$TMP/calls.log"; }
  smm_reload() { :; }
  smm_health() { return 0; }
  smm_run_validate() { return 0; }
  validate_nvim() { return 0; }
  smm_upgrade_reviews() { echo reviews >> "$TMP/calls.log"; }
  confirm() { return 1; }
}
@test "dirty tree refuses" {
  touch "$SMM_REPO/dirty"
  run cmd_upgrade
  [ "$status" -eq 1 ]; [[ "$output" == *'commit or sync first'* ]]
  ! calls | grep -q '^nix '
}
@test "nvim validation failure restores both locks and aborts" {
  validate_nvim() { return 1; }
  run cmd_upgrade
  [ "$status" -eq 1 ]
  git -C "$SMM_REPO" diff --exit-code
  calls | grep -Fq '+Lazy! restore'
  ! calls | grep -qx build
}
@test "health failure rolls back and restores flake lock" {
  smm_health() { return 1; }
  smm_health_reason() { echo not-running; }
  run cmd_upgrade
  [ "$status" -eq 1 ]; calls | grep -qx 'rollback 42'
  git -C "$SMM_REPO" diff --exit-code
}
@test "no-accessibility waits instead of rollback" {
  smm_health() { [ -f "$TMP/granted" ]; }
  smm_health_reason() { echo no-accessibility; }
  smm_wait_permission() { echo "permission $1" >> "$TMP/calls.log"; touch "$TMP/granted"; }
  run cmd_upgrade
  [ "$status" -eq 0 ]; calls | grep -qx 'permission aerospace'
  ! calls | grep -q rollback
}
@test "casks not upgraded without confirm" {
  run cmd_upgrade
  [ "$status" -eq 0 ]; ! calls | grep -q 'brew upgrade'
}
@test "commit lists changed inputs and plugins and starts with upgrade" {
  sed_inplace '/exit 0/i\
case "$*" in *update*) printf '\''{"plugin":{"commit":"new"}}\\n'\'' > "$SMM_REPO/config/nvim/lazy-lock.json" ;; esac\
' "$TMP/bin/nvim"
  run cmd_upgrade
  [ "$status" -eq 0 ]
  [ "$(git -C "$SMM_REPO" log -1 --format=%s)" = 'upgrade: 1 inputs, 1 plugins' ]
  git -C "$SMM_REPO" log -1 --format=%b | grep -q 'foo old → new'
  git -C "$SMM_REPO" log -1 --format=%b | grep -q 'plugin old → new'
}
@test "missing starter manifest skips starter check" {
  source "$REPO/smm/cmd/upgrade.sh"
  git() {
    case "$1" in ls-remote) echo "git $*" >> "$TMP/calls.log" ;; *) command git "$@" ;; esac
  }
  run cmd_upgrade
  [ "$status" -eq 0 ]
  ! calls | grep -q 'NvChad/starter'
}
@test "accepted casks are validated and recorded" {
  confirm() { return 0; }
  smm_run_validate() { echo "validate $*" >> "$TMP/calls.log"; }
  run cmd_upgrade
  [ "$status" -eq 0 ]; calls | grep -qx 'brew upgrade --cask example'
  calls | grep -q 'validate .* karabiner'
  git -C "$SMM_REPO" log -1 --format=%b | grep -q 'casks: example'
}
@test "build failure restores locks without switching" {
  smm_build() { return 1; }
  run cmd_upgrade
  [ "$status" -eq 1 ]; git -C "$SMM_REPO" diff --exit-code
  ! calls | grep -qx switch
}
@test "starter commits and newer NvChad branches are review only" {
  source "$REPO/smm/cmd/upgrade.sh"
  make_repo "$TMP/upstream"
  merged=$(git -C "$TMP/upstream" rev-parse HEAD)
  echo change > "$TMP/upstream/new-file"
  git -C "$TMP/upstream" add -A; git -C "$TMP/upstream" commit -qm 'Starter improvement'
  jq -n --arg upstream "$TMP/upstream" --arg merged "$merged" '{upstream:$upstream,branch:"smm-test",merged:$merged}' > "$SMM_REPO/manifest/nvchad-starter.json"
  echo 'branch = "v2.5",' > "$SMM_REPO/config/nvim/init.lua"
  git() {
    if [ "$1" = ls-remote ] && [ "$2" = --heads ]; then
      printf 'abc\trefs/heads/v2.4\ndef\trefs/heads/v2.6\nghi\trefs/heads/v2.10\n'
    else command git "$@"; fi
  }
  before=$(shasum "$SMM_REPO/manifest/nvchad-starter.json" "$SMM_REPO/config/nvim/init.lua")
  run smm_upgrade_reviews; [ "$status" -eq 0 ]
  [[ "$output" == *'review only, not applied'*'Starter improvement'*'new-file'* ]]
  [[ "$output" == *'branch available: v2.6'*'branch available: v2.10'* ]]
  [[ "$output" != *'branch available: v2.4'* ]]
  [ "$(shasum "$SMM_REPO/manifest/nvchad-starter.json" "$SMM_REPO/config/nvim/init.lua")" = "$before" ]
}
@test "validation uses the freshly built app binaries" {
  smm_build() {
    mkdir -p "$TMP/built/sw/bin"
    cp "$TMP/bin/ghostty" "$TMP/built/sw/bin/ghostty"
    echo "$TMP/built" > "$SMM_STATE/last-build"
  }
  smm_run_validate() { [ "$(command -v ghostty)" = "$TMP/built/sw/bin/ghostty" ]; }
  run cmd_upgrade; [ "$status" -eq 0 ]
}
