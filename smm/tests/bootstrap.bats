#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  stub uname 0 arm64
  stub curl 99
}
@test "bootstrap dry run describes five steps without changing HOME or invoking nix" {
  run bash "$REPO/bootstrap.sh" --dry-run
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 5 ]
  [[ "$output" == *'arm64'*'Determinate'*'profile'*'clone'*'setup'* ]]
  [ -z "$(find "$HOME" -mindepth 1 -print)" ]
  ! calls | grep -Eq '^(curl|nix|sudo|brew) '
}
@test "bootstrap refuses unsupported architecture and unknown arguments" {
  stub uname 0 x86_64
  run bash "$REPO/bootstrap.sh" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *arm64* ]]
  run bash "$REPO/bootstrap.sh" --unknown
  [ "$status" -eq 2 ]
}
@test "retired installer only directs user to smm" {
  # Inspect before execution so a regression cannot run a live installer.
  [ "$(wc -l < "$REPO/setup-my-mac.sh" | tr -d ' ')" -eq 3 ]
  rg -q '^exit 1$' "$REPO/setup-my-mac.sh"
  run bash "$REPO/setup-my-mac.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *'use smm; see README'* ]]
  [ -z "$(calls)" ]
}
@test "README documents bootstrap migration commands and limits" {
  for pattern in 'bootstrap.sh | bash' 'smm setup --preview' 'smm apply' 'smm sync' 'smm add' 'smm remove' 'smm status' 'smm upgrade' 'smm undo' 'App Store' 'iCloud' 'rolled back'; do
    rg -Fq "$pattern" "$REPO/README.md"
  done
  ! rg -q 'MasonInstallAll|TSInstall|personal access token' "$REPO/README.md"
}
