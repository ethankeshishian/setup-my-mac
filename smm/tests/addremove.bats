#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$HOME/Repos/setup-my-mac"
  make_repo "$SMM_REPO"
  mkdir -p "$SMM_REPO/manifest" "$SMM_REPO/config" "$HOME/.config"
  printf '[]\n' > "$SMM_REPO/manifest/links.json"
  export SMM_APPLY_CMD="$TMP/apply"
  cat > "$TMP/apply" <<'SCRIPT'
#!/usr/bin/env bash
[ ! -f "$TMP/fail-apply" ] || exit 1
# Simulate home-manager: remove obsolete links, then create declared links.
while IFS= read -r -d '' file; do
  case "$(readlink "$file")" in "$SMM_REPO"/config/*) rm "$file" ;; esac
done < <(find "$HOME" -type l -print0)
while IFS=$'\t' read -r source target; do
  [ -n "$source" ] || continue
  mkdir -p "$(dirname "$HOME/$target")"
  ln -s "$SMM_REPO/$source" "$HOME/$target" || exit 1
done < <(jq -r '.[] | [.source,.target] | @tsv' "$SMM_REPO/manifest/links.json")
SCRIPT
  chmod +x "$TMP/apply"
  for file in "$REPO"/smm/lib/*.sh "$REPO"/smm/cmd/*.sh; do source "$file"; done
}
@test "add creates manifest entry source and linked target without staging" {
  printf content > "$HOME/.config/test app"
  run "$REPO/smm/bin/smm" add "$HOME/.config/test app" --name test-app
  [ "$status" -eq 0 ]
  jq -e '.[0] == {name:"test-app",source:"config/test app",target:".config/test app",type:"file",validator:null,reload:null}' "$SMM_REPO/manifest/links.json"
  [ "$(cat "$SMM_REPO/config/test app")" = content ]
  [ -L "$HOME/.config/test app" ]
  [ -z "$(git -C "$SMM_REPO" diff --cached --name-only)" ]
}
@test "add directory and default dotfile name" {
  mkdir "$HOME/.config/example"
  printf nested > "$HOME/.config/example/file"
  cmd_add "$HOME/.config/example"
  [ -L "$HOME/.config/example" ]
  [ "$(cat "$SMM_REPO/config/example/file")" = nested ]
  printf dotfile > "$HOME/.example"
  cmd_add "$HOME/.example" --name example-dotfile
  [ -L "$HOME/.example" ]
}
@test "add rejects already linked path" {
  printf content > "$HOME/.config/example"
  cmd_add "$HOME/.config/example"
  run cmd_add "$HOME/.config/example"
  [ "$status" -ne 0 ]
  [ "$(jq length "$SMM_REPO/manifest/links.json")" -eq 1 ]
}
@test "add rejects path outside HOME including parent symlink escape" {
  printf outside > "$TMP/outside"
  run cmd_add "$TMP/outside"
  [ "$status" -ne 0 ]
  ln -s "$TMP" "$HOME/escape"
  run cmd_add "$HOME/escape/outside"
  [ "$status" -ne 0 ]
}
@test "add failure restores original and manifest" {
  printf content > "$HOME/.config/example"
  touch "$TMP/fail-apply"
  run cmd_add "$HOME/.config/example"
  [ "$status" -ne 0 ]
  [ ! -L "$HOME/.config/example" ]
  [ "$(cat "$HOME/.config/example")" = content ]
  [ "$(jq length "$SMM_REPO/manifest/links.json")" -eq 0 ]
  [ ! -e "$SMM_REPO/config/example" ]
}
@test "add refuses source name and managed path collisions" {
  printf original > "$SMM_REPO/config/example"
  printf local > "$HOME/.config/example"
  run cmd_add "$HOME/.config/example"
  [ "$status" -ne 0 ]
  [ "$(cat "$SMM_REPO/config/example")" = original ]
  [ "$(cat "$HOME/.config/example")" = local ]
}
@test "remove keep file leaves regular file with same content" {
  printf content > "$HOME/.config/example"
  cmd_add "$HOME/.config/example"
  choose() { printf 'keep file\n'; }
  run cmd_remove example
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.config/example" ]
  [ "$(cat "$HOME/.config/example")" = content ]
  [ ! -e "$SMM_REPO/config/example" ]
  [ "$(jq length "$SMM_REPO/manifest/links.json")" -eq 0 ]
}
@test "remove delete leaves nothing" {
  mkdir "$HOME/.config/example"
  printf content > "$HOME/.config/example/file"
  cmd_add "$HOME/.config/example"
  choose() { printf 'delete\n'; }
  run cmd_remove example
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.config/example" ]
  [ ! -e "$SMM_REPO/config/example" ]
}
@test "remove failure restores manifest and preserves source" {
  printf content > "$HOME/.config/example"
  cmd_add "$HOME/.config/example"
  touch "$TMP/fail-apply"
  choose() { printf 'delete\n'; }
  run cmd_remove example
  [ "$status" -ne 0 ]
  [ "$(jq length "$SMM_REPO/manifest/links.json")" -eq 1 ]
  [ "$(cat "$HOME/.config/example")" = content ]
}
@test "remove refuses drifted target and unknown name" {
  printf content > "$HOME/.config/example"
  cmd_add "$HOME/.config/example"
  rm "$HOME/.config/example"
  printf tweak > "$HOME/.config/example"
  choose() { printf 'delete\n'; }
  run cmd_remove example
  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/.config/example")" = tweak ]
  run cmd_remove missing
  [ "$status" -ne 0 ]
}
@test "add refuses apply success without the expected link and keeps backup on failure" {
  printf content > "$HOME/.config/example"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$TMP/apply"
  run cmd_add "$HOME/.config/example"
  [ "$status" -ne 0 ]
  [ ! -L "$HOME/.config/example" ]
  [ "$(cat "$HOME/.config/example")" = content ]
  [ -n "$(find "$HOME/.smm-backup" -name original -type f -print)" ]
}
@test "remove refuses target parent symlink escaping HOME" {
  printf content > "$HOME/.config/example"
  cmd_add "$HOME/.config/example"
  mv "$HOME/.config" "$TMP/escaped-config"
  ln -s "$TMP/escaped-config" "$HOME/.config"
  choose() { printf 'delete\n'; }
  run cmd_remove example
  [ "$status" -ne 0 ]
  [ "$(cat "$TMP/escaped-config/example")" = content ]
}
@test "review 12 add accepts indirect home-manager links" {
  python3 - "$TMP/apply" <<'PY'
import sys
p=sys.argv[1]
s=open(p).read().replace('ln -s "$SMM_REPO/$source" "$HOME/$target"', 'ln -sf "$SMM_REPO/$source" "$TMP/store-link"\n  ln -s "$TMP/store-link" "$HOME/$target"')
open(p,'w').write(s)
PY
  printf content > "$HOME/.config/example"
  run cmd_add "$HOME/.config/example"
  [ "$status" -eq 0 ]; [ -L "$HOME/.config/example" ]
}
@test "review 12 remove accepts indirect home-manager links" {
  printf content > "$HOME/.config/example"
  cmd_add "$HOME/.config/example"
  rm "$HOME/.config/example"
  ln -s "$SMM_REPO/config/example" "$TMP/store-link"
  ln -s "$TMP/store-link" "$HOME/.config/example"
  choose() { echo 'keep file'; }
  smm_run_apply() { :; }
  run cmd_remove example
  [ "$status" -eq 0 ]; [ ! -L "$HOME/.config/example" ]
  [ "$(cat "$HOME/.config/example")" = content ]
}
