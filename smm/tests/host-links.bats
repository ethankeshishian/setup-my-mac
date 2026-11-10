#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo" SMM_HOST=Test-Mac
  make_repo "$SMM_REPO"
  mkdir -p "$SMM_REPO/manifest" "$SMM_REPO/config/zsh" "$SMM_REPO/hosts"
  cp "$REPO/hosts/template.nix" "$SMM_REPO/hosts/template.nix"
  echo '[{"name":"zsh","source":"config/zsh/{host}.zshrc","target":".zshrc","type":"file","validator":"zsh","reload":null}]' > "$SMM_REPO/manifest/links.json"
  echo 'echo repo' > "$SMM_REPO/config/zsh/Test-Mac.zshrc"
  for file in "$REPO"/smm/lib/*.sh "$REPO"/smm/cmd/*.sh; do source "$file"; done
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm fixture
}
@test "link_source resolves host and leaves ordinary sources intact" {
  [ "$(link_source zsh)" = config/zsh/Test-Mac.zshrc ]
  stub scutil 0 Mercury
  unset SMM_HOST
  [ "$(link_source zsh)" = config/zsh/Mercury.zshrc ]
  echo '[{"name":"plain","source":"config/plain"}]' > "$SMM_REPO/manifest/links.json"
  [ "$(link_source plain)" = config/plain ]
}
@test "link_source rejects a host that escapes the source directory" {
  export SMM_HOST=../escape
  run link_source zsh
  [ "$status" -ne 0 ]
}
@test "validate resolves host using the candidate root manifest" {
  cp -R "$SMM_REPO" "$TMP/candidate"
  echo 'echo candidate' > "$TMP/candidate/config/zsh/Test-Mac.zshrc"
  echo '[]' > "$SMM_REPO/manifest/links.json"
  validate_zsh() { [ "$(cat "$1")" = 'echo candidate' ]; }
  run smm_validate "$TMP/candidate" zsh
  [ "$status" -eq 0 ]; [ "$output" = 'ok zsh' ]
}
@test "migration compares and resolves the current host source only" {
  cp "$SMM_REPO/config/zsh/Test-Mac.zshrc" "$HOME/.zshrc"
  [ "$(smm_migrate_status zsh)" = same ]
  echo 'echo mercury' > "$SMM_REPO/config/zsh/Mercury.zshrc"
  echo 'echo local' > "$HOME/.zshrc"
  choose() { echo 'use this Mac'; }
  run smm_migrate_resolve zsh
  [ "$status" -eq 0 ]
  [ "$(cat "$SMM_REPO/config/zsh/Test-Mac.zshrc")" = 'echo local' ]
  [ "$(cat "$SMM_REPO/config/zsh/Mercury.zshrc")" = 'echo mercury' ]
}
@test "status accepts the resolved host link" {
  echo '[]' > "$SMM_REPO/manifest/secrets.json"
  ln -s "$SMM_REPO/config/zsh/Test-Mac.zshrc" "$HOME/.zshrc"
  smm_brew_undeclared() { :; }; stub gh 0
  run cmd_status
  [ "$status" -eq 0 ]; [[ "$output" != *'broken links'* ]]
}
@test "remove operates on the current host file and preserves other hosts" {
  echo mercury > "$SMM_REPO/config/zsh/Mercury.zshrc"
  ln -s "$SMM_REPO/config/zsh/Test-Mac.zshrc" "$HOME/.zshrc"
  choose() { echo 'keep file'; }; smm_run_apply() { :; }
  run cmd_remove zsh
  [ "$status" -eq 0 ]; [ ! -L "$HOME/.zshrc" ]
  [ "$(cat "$HOME/.zshrc")" = 'echo repo' ]
  [ ! -e "$SMM_REPO/config/zsh/Test-Mac.zshrc" ]
  [ "$(cat "$SMM_REPO/config/zsh/Mercury.zshrc")" = mercury ]
}
@test "add refuses to overlap a resolved host source" {
  echo local > "$HOME/.other"
  # This ordinary path maps into the existing host's templated source.
  mkdir -p "$HOME/.config/zsh"
  echo local > "$HOME/.config/zsh/Test-Mac.zshrc"
  rm "$SMM_REPO/config/zsh/Test-Mac.zshrc"
  run cmd_add "$HOME/.config/zsh/Test-Mac.zshrc" --name duplicate
  [ "$status" -ne 0 ]; [[ "$output" == *overlaps* ]]
}
@test "host setup seeds a missing host zshrc without overwriting it" {
  smm_seed_host_zsh Test-Mac
  [ "$(cat "$SMM_REPO/config/zsh/Test-Mac.zshrc")" = 'echo repo' ]
  echo live > "$HOME/.zshrc"
  smm_seed_host_zsh New-Mac
  [ "$(tail -n 1 "$SMM_REPO/config/zsh/New-Mac.zshrc")" = live ]
  rg -Fx '[ -f ~/.config/zsh/common.zsh ] && source ~/.config/zsh/common.zsh' "$SMM_REPO/config/zsh/New-Mac.zshrc"
  rm "$HOME/.zshrc"
  smm_seed_host_zsh Fresh-Mac
  rg '^#' "$SMM_REPO/config/zsh/Fresh-Mac.zshrc"
  rg -Fx '[ -f ~/.config/zsh/common.zsh ] && source ~/.config/zsh/common.zsh' "$SMM_REPO/config/zsh/Fresh-Mac.zshrc"
}
