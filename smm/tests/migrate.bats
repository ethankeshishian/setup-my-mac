#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo" SMM_BACKUP="$TMP/backup"
  make_repo "$SMM_REPO"
  mkdir -p "$SMM_REPO/config" "$SMM_REPO/manifest"
  echo '[{"name":"test","source":"config/test","target":".test","type":"file"}]' > "$SMM_REPO/manifest/links.json"
  echo '{"taps":[],"brews":[],"casks":[]}' > "$SMM_REPO/manifest/homebrew.json"
  echo '["neovim","jankyborders"]' > "$SMM_REPO/manifest/nix-packages.json"
  echo original > "$SMM_REPO/config/test"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm baseline
  cp "$SMM_REPO/config/test" "$HOME/.test"
  for lib in "$REPO"/smm/lib/*.sh; do source "$lib"; done
  stub brew 0
}
@test "same" { run smm_migrate_status test; [ "$output" = same ]; }
@test "repo-newer detected from history" {
  echo updated > "$SMM_REPO/config/test"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm updated
  run smm_migrate_status test; [ "$output" = repo-newer ]
}
@test "local-newer" {
  echo local > "$HOME/.test"
  run smm_migrate_status test; [ "$output" = local-newer ]
}
@test "both-changed" {
  echo local > "$HOME/.test"; touch -t 200001010000 "$HOME/.test"
  run smm_migrate_status test; [ "$output" = both-changed ]
}
@test "linked and missing" {
  rm "$HOME/.test"; run smm_migrate_status test; [ "$output" = missing ]
  ln -s "$SMM_REPO/config/test" "$HOME/.test"
  run smm_migrate_status test; [ "$output" = linked ]
}
@test "resolve backs up and retains target until activation and keeps local selection" {
  echo local > "$HOME/.test"
  choose() { echo 'use this Mac'; }
  run smm_migrate_resolve test; [ "$status" -eq 0 ]
  [[ "$output" == *'-original'*'+local'* ]]
  [ "$(cat "$SMM_BACKUP/.test")" = local ]; [ -e "$HOME/.test" ]
  [ "$(cat "$SMM_REPO/config/test")" = local ]
}
@test "pick changes keeps only chosen hunks" {
  seq 1 30 > "$SMM_REPO/config/test"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm lines
  sed '2s/.*/first/;28s/.*/second/' "$SMM_REPO/config/test" > "$HOME/.test"
  choose() { echo 'pick changes'; }
  run smm_migrate_resolve test <<< $'y\nn\n'
  [ "$status" -eq 0 ]
  [ "$(sed -n '2p' "$SMM_REPO/config/test")" = first ]
  [ "$(sed -n '28p' "$SMM_REPO/config/test")" = 28 ]
  [ "$(sed -n '28p' "$SMM_BACKUP/.test")" = second ]
}
@test "preview changes nothing in HOME or repo" {
  before=$(find "$HOME" "$SMM_REPO" -type f -exec shasum {} + | sort | shasum)
  run smm_migrate_preview; [ "$status" -eq 0 ]; [[ "$output" == *'test same'* ]]
  [ "$(find "$HOME" "$SMM_REPO" -type f -exec shasum {} + | sort | shasum)" = "$before" ]
}
@test "directories use worst per-file status including additions" {
  rm "$SMM_REPO/config/test" "$HOME/.test"
  mkdir "$SMM_REPO/config/test" "$HOME/.test"
  echo same > "$SMM_REPO/config/test/a"; echo old > "$SMM_REPO/config/test/b"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm directory
  cp -a "$SMM_REPO/config/test/." "$HOME/.test/"
  echo new > "$HOME/.test/b"
  run smm_migrate_status test; [ "$output" = local-newer ]
  echo extra > "$HOME/.test/c"
  run smm_migrate_status test; [ "$output" = local-newer ]
}
@test "lazylock takes descendant and preserves repo on divergence or missing plugin" {
  mkdir -p "$HOME/.local/share/nvim/lazy"
  plugin="$HOME/.local/share/nvim/lazy/plugin"
  make_repo "$plugin"; old=$(git -C "$plugin" rev-parse HEAD)
  git -C "$plugin" commit -qm newer --allow-empty; new=$(git -C "$plugin" rev-parse HEAD)
  printf '{"plugin":{"commit":"%s"},"missing":{"commit":"local"}}\n' "$new" > "$TMP/local.json"
  printf '{"plugin":{"commit":"%s"},"missing":{"commit":"repo"}}\n' "$old" > "$TMP/repo.json"
  run smm_migrate_lazylock "$TMP/local.json" "$TMP/repo.json"; [ "$status" -eq 0 ]
  [ "$(jq -r .plugin.commit "$TMP/repo.json")" = "$new" ]
  [ "$(jq -r .missing.commit "$TMP/repo.json")" = repo ]
}
@test "backup failure leaves local config untouched" {
  echo local > "$HOME/.test"; echo blocked > "$SMM_BACKUP"
  choose() { echo 'use repo'; }
  run smm_migrate_resolve test; [ "$status" -ne 0 ]; [ -f "$HOME/.test" ]
}
@test "repo-newer is backed up and resolved without prompting" {
  echo updated > "$SMM_REPO/config/test"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm update
  choose() { return 99; }
  run smm_migrate_resolve test; [ "$status" -eq 0 ]
  [ -e "$HOME/.test" ]; [ "$(cat "$SMM_BACKUP/.test")" = original ]
  [ "$(cat "$SMM_REPO/config/test")" = updated ]
}
@test "lazylock prefers repo when plugin commits have diverged" {
  mkdir -p "$HOME/.local/share/nvim/lazy"
  plugin="$HOME/.local/share/nvim/lazy/plugin"
  make_repo "$plugin"; base=$(git -C "$plugin" rev-parse HEAD)
  git -C "$plugin" commit --allow-empty -qm repo; repo_sha=$(git -C "$plugin" rev-parse HEAD)
  git -C "$plugin" checkout -q --detach "$base"
  git -C "$plugin" commit --allow-empty -qm local; local_sha=$(git -C "$plugin" rev-parse HEAD)
  printf '{"plugin":{"commit":"%s"}}\n' "$local_sha" > "$TMP/local.json"
  printf '{"plugin":{"commit":"%s"}}\n' "$repo_sha" > "$TMP/repo.json"
  run smm_migrate_lazylock "$TMP/local.json" "$TMP/repo.json"; [ "$status" -eq 0 ]
  [ "$(jq -r .plugin.commit "$TMP/repo.json")" = "$repo_sha" ]
}
