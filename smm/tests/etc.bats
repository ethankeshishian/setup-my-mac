#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  export REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo" SMM_HOST=Test-Mac SMM_ETC_ROOT="$TMP/etc"
  mkdir -p "$SMM_REPO/hosts" "$SMM_ETC_ROOT"; cp -R "$REPO/smm" "$SMM_REPO/smm"
  for file in "$REPO"/smm/lib/*.sh "$REPO"/smm/cmd/*.sh; do source "$file"; done
  smm_etc_entries() { echo '{"zshenv":{"target":"zshenv","enable":true,"knownSha256Hashes":[]}}'; }
  export SMM_ANSWERS="$TMP/answers.json"
  echo '{"etc.zshenv":"accept"}' > "$SMM_ANSWERS"
}
@test "etc classifier separates installer stock export and shell code without evaluation" {
  cat > "$SMM_ETC_ROOT/zshenv" <<'TEXT'
# comment

# Nix
if [ -e '/nix/profile' ]; then
 . '/nix/profile'
fi
# End Nix
export AWS_CA_BUNDLE="/Library/Mercury/certs/aws-ca-bundle.pem"
export UNSAFE=$(touch /must-not-run)
echo 'keep ${literal}'
TEXT
  run smm_etc_classify "$SMM_ETC_ROOT/zshenv" zshenv
  [ "$status" -eq 0 ]
  jq -e '.installer | length == 5' <<< "$output"
  jq -e '.variables.AWS_CA_BUNDLE == "/Library/Mercury/certs/aws-ca-bundle.pem"' <<< "$output"
  jq -e '.shell | contains("export UNSAFE=$(touch /must-not-run)\n") and contains("echo '\''keep ${literal}'\''\n")' <<< "$output"
  jq -e '.stock | length == 2' <<< "$output"
}
@test "etc takeover generates escaped Nix preserves file and rebuilds before completion" {
  printf 'export AWS_CA_BUNDLE="/Library/Mercury/certs/aws-ca-bundle.pem"\necho '\''${literal}'\''\n' > "$SMM_ETC_ROOT/zshenv"
  cp "$SMM_ETC_ROOT/zshenv" "$TMP/original"
  step_build_run() { echo rebuilt >> "$TMP/calls.log"; }
  run step_etc_run; [ "$status" -eq 0 ]
  [[ "$output" == *KEEP*AWS_CA_BUNDLE* ]]; [[ "$output" == *KEEP*'echo '* ]]
  file="$SMM_REPO/hosts/etc/Test-Mac.nix"
  [ -f "$file" ]; rg -F 'environment.variables."AWS_CA_BUNDLE"' "$file"
  rg -F 'programs.zsh.shellInit' "$file"; rg -F '\${literal}' "$file"
  sha=$(shasum -a 256 "$SMM_ETC_ROOT/zshenv" | awk '{print $1}')
  rg -F "$sha" "$file"; calls | grep -qx rebuilt
  cmp "$TMP/original" "$SMM_ETC_ROOT/zshenv"
  run step_etc_done; [ "$status" -eq 0 ]
  before=$(shasum "$file"); run step_etc_run; [ "$status" -eq 0 ]; [ "$before" = "$(shasum "$file")" ]
}
@test "declining etc review stops without writing a module or rebuilding" {
  echo 'echo preserve' > "$SMM_ETC_ROOT/zshenv"
  echo '{"etc.zshenv":"stop"}' > "$SMM_ANSWERS"
  step_build_run() { echo rebuilt >> "$TMP/calls.log"; }
  run step_etc_run; [ "$status" -eq 1 ]; [[ "$output" == *'rerun'* ]]
  [ ! -f "$SMM_REPO/hosts/etc/Test-Mac.nix" ]; ! calls | grep -qx rebuilt
}
@test "etc static links known hashes disabled entries and absent files are already fine" {
  mkdir "$SMM_ETC_ROOT/static"; echo data > "$SMM_ETC_ROOT/static/zshenv"
  ln -s "$SMM_ETC_ROOT/static/zshenv" "$SMM_ETC_ROOT/zshenv"
  run step_etc_done; [ "$status" -eq 0 ]
  rm "$SMM_ETC_ROOT/zshenv"; echo data > "$SMM_ETC_ROOT/zshenv"
  export TEST_SHA="$(shasum -a 256 "$SMM_ETC_ROOT/zshenv" | awk '{print $1}')"
  smm_etc_entries() { jq -n --arg sha "$TEST_SHA" '{zshenv:{target:"zshenv",enable:true,knownSha256Hashes:[$sha]}}'; }
  run step_etc_done; [ "$status" -eq 0 ]
  smm_etc_entries() { echo '{"zshenv":{"target":"zshenv","enable":false,"knownSha256Hashes":[]}}'; }
  run step_etc_done; [ "$status" -eq 0 ]
}
@test "unterminated installer blocks and unknown targets preserve all uncertain code" {
  printf '# Nix\necho preserve\n' > "$TMP/file"
  run smm_etc_classify "$TMP/file" other
  [ "$status" -eq 0 ]; jq -e '.installer == [] and (.shell | contains("echo preserve"))' <<< "$output"
}
@test "setup places etc between build and dedupe" {
  smm_setup_steps
  [[ " ${SETUP_STEPS[*]} " == *' build etc dedupe switch '* ]]
}
@test "etc eval projects enabled metadata and uses experimental-feature helper" {
  unset -f smm_etc_entries
  source "$REPO/smm/lib/etc.sh"
  git -C "$SMM_REPO" init -q
  stub nix 0 '{}'
  run smm_etc_entries; [ "$status" -eq 0 ]; [ "$output" = '{}' ]
  calls | grep -Fq "nix --extra-experimental-features nix-command flakes eval --no-write-lock-file --json path:$SMM_STATE/flake."
  calls | grep -Fq 'knownSha256Hashes enable'
}
@test "unknown target with shell code refuses takeover and etc file change requires new review" {
  echo 'echo preserve' > "$SMM_ETC_ROOT/other"
  smm_etc_entries() { echo '{"other":{"target":"other","enable":true,"knownSha256Hashes":[]}}'; }
  echo '{"etc.other":"accept"}' > "$SMM_ANSWERS"
  run step_etc_run; [ "$status" -eq 1 ]; [[ "$output" == *'No shell-init option'* ]]
  [ ! -f "$SMM_REPO/hosts/etc/Test-Mac.nix" ]
}
@test "etc static links remain fine when static itself points into the store" {
  mkdir "$TMP/store-etc"; echo data > "$TMP/store-etc/zshenv"
  ln -s "$TMP/store-etc" "$SMM_ETC_ROOT/static"
  ln -s "$SMM_ETC_ROOT/static/zshenv" "$SMM_ETC_ROOT/zshenv"
  run step_etc_done; [ "$status" -eq 0 ]
}
@test "changed etc content requests new approval and replaces only that module section" {
  step_build_run() { return 0; }
  echo 'export FIRST=one' > "$SMM_ETC_ROOT/zshenv"
  run step_etc_run; [ "$status" -eq 0 ]
  echo 'export FIRST=two' > "$SMM_ETC_ROOT/zshenv"
  echo '{}' > "$SMM_ANSWERS"
  run step_etc_done; [ "$status" -ne 0 ]
  run step_etc_run; [ "$status" -eq 3 ]
  echo '{"etc.zshenv":"accept"}' > "$SMM_ANSWERS"
  run step_etc_run; [ "$status" -eq 0 ]
  [ "$(rg -c 'environment.variables."FIRST"' "$SMM_REPO/hosts/etc/Test-Mac.nix")" -eq 1 ]
  rg -F '"two"' "$SMM_REPO/hosts/etc/Test-Mac.nix"
}

@test "SSH-only installer block is dropped without dropping surrounding user code" {
  cat > "$SMM_ETC_ROOT/zshenv" <<'TEXT'
export BEFORE=yes
# Set up Nix only on SSH connections
# See https://github.com/DeterminateSystems/nix-installer
if [ -n "$SSH_CONNECTION" ]; then
  if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  fi
fi
export AFTER=yes
TEXT
  run smm_etc_classify "$SMM_ETC_ROOT/zshenv" zshenv
  [ "$status" -eq 0 ]
  jq -e '.installer | length == 7' <<< "$output"
  jq -e '.shell == "" and .variables == {BEFORE:"yes",AFTER:"yes"}' <<< "$output"
}
@test "macOS stock shell fixtures are dropped and user additions are preserved" {
  for shell in bashrc zshrc zprofile; do
    cat "$REPO/smm/tests/fixtures/etc/$shell" > "$SMM_ETC_ROOT/$shell"
    echo 'echo custom-work-init' >> "$SMM_ETC_ROOT/$shell"
    run smm_etc_classify "$SMM_ETC_ROOT/$shell" "$shell"
    [ "$status" -eq 0 ]
    jq -e '.shell == "echo custom-work-init\n" and .variables == {} and all(.review[:-1][]; .action == "DROP")' <<< "$output"
  done
}
@test "etc review CLI shows accepted known and pending managed files read-only" {
  git -C "$SMM_REPO" init -q
  echo '# stock comment' > "$SMM_ETC_ROOT/zshenv"
  echo 'export WORK=keep' >> "$SMM_ETC_ROOT/zshenv"
  stub nix 0 '{"zshenv":{"enable":true,"target":"zshenv","knownSha256Hashes":[]}}'
  before=$(shasum "$SMM_ETC_ROOT/zshenv")
  run "$REPO/smm/bin/smm" etc review
  [ "$status" -eq 0 ]
  [[ "$output" == *'zshenv: pending (decision needed)'*DROP*KEEP*WORK=keep* ]] || return 1
  [ "$before" = "$(shasum "$SMM_ETC_ROOT/zshenv")" ]
  ! calls | grep -Eq 'sudo|build|switch'
  [ ! -d "$SMM_REPO/hosts/etc" ]
}
@test "unterminated SSH installer blocks preserve uncertain user shell code" {
  printf '# Set up Nix only on SSH connections\nif [ -n "$SSH_CONNECTION" ]; then\n  echo preserve\n' > "$TMP/file"
  run smm_etc_classify "$TMP/file" zshenv
  [ "$status" -eq 0 ]
  jq -e '.installer == [] and (.shell | contains("echo preserve"))' <<< "$output"
}
@test "unknown shell conditionals keep their stock-looking else and fi lines intact" {
  cat > "$SMM_ETC_ROOT/zshrc" <<'TEXT'
if [[ -n "$WORK_PROFILE" ]]; then
    export WORK_ACCOUNT=custom
else
    echo use-default-account
fi
TEXT
  run smm_etc_classify "$SMM_ETC_ROOT/zshrc" zshrc
  [ "$status" -eq 0 ]
  jq -e --rawfile original "$SMM_ETC_ROOT/zshrc" '.shell == $original and .variables == {} and all(.review[]; .action == "KEEP")' <<< "$output"
}
@test "etc review evaluates a snapshot without ignored files and never writes a lock" {
  git -C "$SMM_REPO" init -q
  echo 'secret.env' > "$SMM_REPO/.gitignore"
  echo 'TOKEN=hunter2' > "$SMM_REPO/secret.env"
  echo '{ }' > "$SMM_REPO/flake.nix"
  git -C "$SMM_REPO" add .gitignore flake.nix
  before=$(git -C "$SMM_REPO" status --porcelain --ignored)
  cat > "$TMP/bin/nix" <<'STUB'
#!/usr/bin/env bash
printf 'nix %s\n' "$*" >> "$TMP/calls.log"
for arg; do case "$arg" in path:*) src=${arg#path:}; src=${src%%#*}; find "$src" -type f >> "$TMP/source.txt" ;; esac; done
echo '{"zshenv":{"enable":true,"target":"zshenv","knownSha256Hashes":[]}}'
STUB
  chmod +x "$TMP/bin/nix"
  echo 'export WORK=keep' > "$SMM_ETC_ROOT/zshenv"
  unset -f smm_etc_entries
  run "$REPO/smm/bin/smm" etc review
  [ "$status" -eq 0 ]
  calls | grep -q -- '--no-write-lock-file'
  ! calls | grep -qF "path:$SMM_REPO#"
  grep -q '/flake.nix$' "$TMP/source.txt"
  ! grep -q 'secret.env' "$TMP/source.txt"
  [ "$before" = "$(git -C "$SMM_REPO" status --porcelain --ignored)" ]
  [ ! -e "$SMM_REPO/flake.lock" ]
}
@test "etc review labels stock-hash and accepted files instead of implying they are kept" {
  git -C "$SMM_REPO" init -q
  cat "$REPO/smm/tests/fixtures/etc/zprofile" > "$SMM_ETC_ROOT/zprofile"
  echo 'export WORK=keep' > "$SMM_ETC_ROOT/zshenv"
  stock=$(shasum -a 256 "$SMM_ETC_ROOT/zprofile" | awk '{print $1}')
  smm_etc_entries() { printf '{"zprofile":{"enable":true,"target":"zprofile","knownSha256Hashes":["%s"]},"zshenv":{"enable":true,"target":"zshenv","knownSha256Hashes":[]}}\n' "$stock"; }
  step_build_run() { :; }
  step_etc_run
  run smm_etc_review
  [ "$status" -eq 0 ]
  [[ "$output" == *'zprofile: known stock hash: replaced entirely by nix-darwin'* ]] || return 1
  ! [[ "$output" == *path_helper* ]]
  [[ "$output" == *'zshenv: already accepted in hosts/etc/Test-Mac.nix'*KEEP*WORK=keep* ]] || return 1
}
@test "etc paths are appended after Nix paths in path_helper order in bash and zsh" {
  mkdir -p "$TMP/root/paths.d"
  printf '/usr/bin\n/System/Cryptexes/App/usr/bin\n' > "$TMP/root/paths"
  printf '/opt/X11/bin\n' > "$TMP/root/paths.d/40-XQuartz"
  printf '# note\n\n/pkg/env/global/bin' > "$TMP/root/paths.d/10-pmk-global"
  # A deleted working directory from an earlier test makes the shell warn.
  cd "$TMP"
  for shell in /bin/bash /bin/zsh; do
    run env -i PATH=/nix/bin:/usr/bin __smm_etc_root="$TMP/root" "$shell" -c ". '$REPO/modules/darwin/etc-paths.sh'; echo \"\$PATH\"; typeset -f __smm_etc_paths >/dev/null && echo LEAK; :"
    [ "$status" -eq 0 ]
    [ "$output" = /nix/bin:/usr/bin:/System/Cryptexes/App/usr/bin:/pkg/env/global/bin:/opt/X11/bin ] || { echo "shell=$shell output=[$output]"; return 1; }
  done
}
