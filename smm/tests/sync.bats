#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  make_remote_pair
  # The production remote is main; these refs exist only in the temp fixture.
  git --git-dir="$TMP/remote.git" fetch -q "$TMP/seed" smm-test:refs/heads/main
  git --git-dir="$TMP/remote.git" symbolic-ref HEAD refs/heads/main
  for clone in a b; do
    git -C "$TMP/$clone" fetch -q origin
    git -C "$TMP/$clone" checkout -qb main origin/main
  done
  export SMM_REPO="$TMP/a"
  export SMM_VALIDATE_CMD="$TMP/validate" SMM_APPLY_CMD="$TMP/apply"
  cat > "$TMP/validate" <<'SCRIPT'
#!/usr/bin/env bash
printf 'validate %s\n' "$1" >> "$TMP/calls.log"
if [ -f "$1/config.txt" ] && grep -q invalid "$1/config.txt"; then
  echo 'fail fixture: invalid config'; exit 1
fi
SCRIPT
  cat > "$TMP/apply" <<'SCRIPT'
#!/usr/bin/env bash
printf 'apply\n' >> "$TMP/calls.log"
SCRIPT
  chmod +x "$TMP/validate" "$TMP/apply"
  # Never execute git push, even against a local fixture. Emulate receipt by
  # fetching HEAD into the temporary bare remote. All other git is real.
  export TEST_REAL_GIT
  TEST_REAL_GIT=$(command -v git)
  cat > "$TMP/bin/git" <<'SCRIPT'
#!/usr/bin/env bash
if [ "${1:-}" = push ]; then
  printf 'git push (emulated locally)\n' >> "$TMP/calls.log"
  remote=$("$TEST_REAL_GIT" remote get-url origin) || exit 1
  [ "$remote" = "$TMP/remote.git" ] || exit 99
  exec "$TEST_REAL_GIT" --git-dir="$remote" fetch -q "$SMM_REPO" HEAD:refs/heads/main
fi
exec "$TEST_REAL_GIT" "$@"
SCRIPT
  chmod +x "$TMP/bin/git"
  for file in "$REPO"/smm/lib/*.sh "$REPO"/smm/cmd/*.sh; do source "$file"; done
  stub gh 0
  stub scutil 0 Test-Mac
  stub darwin-rebuild 0 '42 date (current)'
  sed -i '' '/exit 0/i\
if [ "$1" = build ]; then mkdir -p result/sw/bin; fi\
' "$TMP/bin/darwin-rebuild"
  stub gitleaks 0
  mkdir -p "$SMM_REPO/manifest"
  printf '[]\n' > "$SMM_REPO/manifest/secrets.json"
  printf '[]\n' > "$SMM_REPO/manifest/links.json"
  fixture_commit "$TMP/a" baseline
  publish_fixture "$TMP/a"
  git -C "$TMP/b" pull -q --ff-only origin main
}
fixture_commit() {
  git -C "$1" add -A
  git -C "$1" -c commit.gpgsign=false commit -qm "$2"
}
publish_fixture() { git --git-dir="$TMP/remote.git" fetch -q "$1" HEAD:refs/heads/main; }
@test "prompts for message when there are changes" {
  printf changed > "$SMM_REPO/config.txt"
  export SMM_TEST_TTY_INPUT='My config'
  run run_tty /bin/bash "$REPO/smm/bin/smm" sync
  [ "$status" -eq 0 ]
  [[ "$output" == *'Commit message:'* ]]
  [ "$(git -C "$SMM_REPO" log -1 --format=%s)" = 'My config' ]
}
@test "message flag skips prompt" {
  printf changed > "$SMM_REPO/config.txt"
  run "$REPO/smm/bin/smm" sync -m 'My config'
  [ "$status" -eq 0 ]
  [[ "$output" != *'Commit message:'* ]]
}
@test "nothing to commit does not prompt and applies" {
  run cmd_sync </dev/null
  [ "$status" -eq 0 ]
  [[ "$output" != *'Commit message:'* ]]
  calls | grep -qx apply
}
@test "round trip a to b" {
  printf changed > "$TMP/a/config.txt"
  cmd_sync -m transfer
  export SMM_REPO="$TMP/b"
  cmd_sync
  [ "$(cat "$TMP/b/config.txt")" = changed ]
}
@test "invalid incoming leaves main tree unchanged and removes worktree" {
  printf invalid > "$TMP/b/config.txt"
  fixture_commit "$TMP/b" invalid
  publish_fixture "$TMP/b"
  before=$(git -C "$SMM_REPO" rev-parse HEAD)
  run cmd_sync
  [ "$status" -eq 1 ]
  [[ "$output" == *'incoming change breaks fixture; this Mac stays as is'* ]]
  [ "$(git -C "$SMM_REPO" rev-parse HEAD)" = "$before" ]
  [ ! -e "$SMM_REPO/config.txt" ]
  [ ! -e "$SMM_STATE/sync-wt" ]
}
@test "local invalid refuses before commit" {
  printf invalid > "$SMM_REPO/config.txt"
  before=$(git -C "$SMM_REPO" rev-parse HEAD)
  run cmd_sync -m invalid
  [ "$status" -eq 1 ]
  [[ "$output" == *'fix fixture before syncing'* ]]
  [ "$(git -C "$SMM_REPO" rev-parse HEAD)" = "$before" ]
}
@test "conflict keep theirs" {
  printf baseline > "$TMP/a/config.txt"
  fixture_commit "$TMP/a" initial
  publish_fixture "$TMP/a"
  git -C "$TMP/b" pull -q --ff-only origin main
  printf theirs > "$TMP/b/config.txt"
  fixture_commit "$TMP/b" theirs
  publish_fixture "$TMP/b"
  printf mine > "$TMP/a/config.txt"
  choose() { printf 'keep theirs\n'; }
  run cmd_sync -m mine
  [ "$status" -eq 0 ]
  [[ "$output" == *'config.txt'* ]]
  [ "$(cat "$TMP/a/config.txt")" = theirs ]
  [ ! -e "$SMM_STATE/sync-wt" ]
}
@test "secret in outgoing blocks push" {
  before=$(git --git-dir="$TMP/remote.git" rev-parse main)
  printf private > "$SMM_REPO/weather.env.sh"
  run cmd_sync -m secret
  [ "$status" -eq 1 ]
  [ "$(git --git-dir="$TMP/remote.git" rev-parse main)" = "$before" ]
  ! calls | grep -q 'git push'
}
@test "unreachable remote changes nothing including dirty index" {
  printf changed > "$SMM_REPO/config.txt"
  git -C "$SMM_REPO" remote set-url origin "$TMP/missing.git"
  before=$(git -C "$SMM_REPO" rev-parse HEAD)
  index=$(git -C "$SMM_REPO" status --porcelain)
  run cmd_sync -m offline
  [ "$status" -eq 1 ]
  [[ "$output" == *"can't reach GitHub; nothing changed"* ]]
  [ "$(git -C "$SMM_REPO" rev-parse HEAD)" = "$before" ]
  [ "$(git -C "$SMM_REPO" status --porcelain)" = "$index" ]
}
@test "empty commit message aborts and signed out blocks push" {
  printf changed > "$SMM_REPO/config.txt"
  run cmd_sync -m ''
  [ "$status" -ne 0 ]
  stub gh 1
  run cmd_sync -m signed-out
  [ "$status" -ne 0 ]
  ! calls | grep -q 'git push'
}
@test "interrupted worktree creation is cleaned before returning" {
  python3 - "$TMP/bin/git" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.replace('exec "$TEST_REAL_GIT" "$@"', '''if [ "${1:-}" = -C ] && [ "${3:-}" = worktree ] && [ "${4:-}" = add ]; then
  "$TEST_REAL_GIT" "$@" || exit 1
  kill -TERM "$PPID"
  exit 0
fi
exec "$TEST_REAL_GIT" "$@"''')
open(p, 'w').write(s)
PY
  run "$REPO/smm/bin/smm" sync
  [ "$status" -ne 0 ]
  [ ! -e "$SMM_STATE/sync-wt" ]
  ! git -C "$SMM_REPO" worktree list --porcelain | grep -q '/sync-wt$'
}
@test "review 4 candidate build failure never reaches live tree" {
  printf incoming > "$TMP/b/config.txt"
  fixture_commit "$TMP/b" incoming; publish_fixture "$TMP/b"
  before=$(git -C "$SMM_REPO" rev-parse HEAD)
  smm_build() { echo "build $(smm_repo)" >> "$TMP/calls.log"; return 1; }
  run cmd_sync
  [ "$status" -eq 1 ]; [ "$(git -C "$SMM_REPO" rev-parse HEAD)" = "$before" ]
  [ ! -e "$SMM_REPO/config.txt" ]; [ ! -e "$SMM_STATE/sync-wt" ]
  calls | grep -qx "build $SMM_STATE/sync-wt"
}
@test "review 4 later activation failure resets live tree preserving user's commit on backup ref" {
  printf incoming > "$TMP/b/incoming.txt"
  fixture_commit "$TMP/b" incoming; publish_fixture "$TMP/b"
  printf own > "$SMM_REPO/own.txt"
  smm_build() { :; }; smm_use_build_tools() { :; }
  smm_run_apply() { return 1; }
  smm_generation() { echo 42; }; smm_rollback() { echo "rollback $1" >> "$TMP/calls.log"; }
  before=$(git -C "$SMM_REPO" rev-parse HEAD)
  run cmd_sync -m mine
  [ "$status" -eq 1 ]; [ "$(git -C "$SMM_REPO" rev-parse HEAD)" = "$before" ]
  [ ! -e "$SMM_REPO/incoming.txt" ]
  [ "$(git -C "$SMM_REPO" show refs/smm/pre-sync:own.txt)" = own ]
  calls | grep -qx 'rollback 42'
  ! calls | grep -q 'git push'
}
@test "review 4 incoming validation uses candidate system executables" {
  printf incoming > "$TMP/b/config.txt"
  fixture_commit "$TMP/b" incoming; publish_fixture "$TMP/b"
  smm_build() {
    mkdir -p "$TMP/candidate/sw/bin"
    printf '#!/usr/bin/env bash\nprintf candidate > "$TMP/version-used"\n' > "$TMP/candidate/sw/bin/ghostty"
    chmod +x "$TMP/candidate/sw/bin/ghostty"
    echo "$TMP/candidate" > "$SMM_STATE/last-build"
  }
  smm_run_validate() {
    [ "${2:-}" != aerospace ] || return 0
    validate_ghostty "$1/config"
  }
  run cmd_sync
  [ "$status" -eq 0 ]; [ "$(cat "$TMP/version-used")" = candidate ]
  [ "$(cat "$SMM_REPO/config.txt")" = incoming ]
}
@test "review 4 candidate failure preserves the user's committed live edits" {
  printf incoming > "$TMP/b/incoming.txt"
  fixture_commit "$TMP/b" incoming; publish_fixture "$TMP/b"
  printf own > "$SMM_REPO/own.txt"
  smm_build() { return 1; }
  run cmd_sync -m mine
  [ "$status" -eq 1 ]; [ "$(cat "$SMM_REPO/own.txt")" = own ]
  [ "$(git -C "$SMM_REPO" log -1 --format=%s)" = mine ]
  [ ! -e "$SMM_REPO/incoming.txt" ]
}
