#!/usr/bin/env bats

load helpers

setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

@test "stub records calls" {
  stub foo 0 hi
  run foo a b
  [ "$status" -eq 0 ]
  [ "$output" = hi ]
  calls | grep -qx "foo a b"
}

@test "stub preserves literal output and exit status" {
  stub foo 7 "literal \$HOME \`uname\`"
  run foo
  [ "$status" -eq 7 ]
  [ "$output" = "literal \$HOME \`uname\`" ]
}

@test "home and system tools are isolated" {
  [ "$HOME" = "$TMP/home" ]
  [ "$SMM_STATE" = "$TMP/state" ]
  for tool in aerospace sketchybar brew darwin-rebuild sudo op gh launchctl osascript scutil systemextensionsctl karabiner_cli ghostty nvim open; do
    [ "$(command -v "$tool")" = "$TMP/bin/$tool" ]
  done
}

@test "make_repo creates a locally configured repository" {
  make_repo "$TMP/repo"
  [ -n "$(git -C "$TMP/repo" rev-parse HEAD)" ]
  [ "$(git -C "$TMP/repo" config --local user.name)" = 'Smm Test' ]
  [ -z "$(git -C "$TMP/repo" status --porcelain)" ]
}

@test "make_remote_pair creates clones of the same initial commit" {
  make_remote_pair
  [ "$(git -C "$TMP/remote.git" rev-parse --is-bare-repository)" = true ]
  [ "$(git -C "$TMP/a" rev-parse HEAD)" = "$(git -C "$TMP/b" rev-parse HEAD)" ]
  [ "$(git -C "$TMP/a" config --local user.email)" = smm-test@example.invalid ]
}

@test "smm runs from another directory through a symlink" {
  ln -s "$REPO/smm/bin/smm" "$TMP/bin/smm"
  cd "$HOME" || return 1
  run smm --help
  [ "$status" -eq 0 ]
  [[ "$output" == *'setup apply sync add remove status upgrade undo validate'* ]]
  run smm nonexistent
  [ "$status" -eq 2 ]
}
