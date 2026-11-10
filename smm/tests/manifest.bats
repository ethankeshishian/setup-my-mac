#!/usr/bin/env bats

load helpers

setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  LINKS="$REPO/manifest/links.json"
}

@test "every link source exists" {
  jq -er '.[].source' "$LINKS" > "$TMP/sources"
  while IFS= read -r source; do
    [ -e "$REPO/$source" ]
  done < "$TMP/sources"
}

@test "link names unique" {
  jq -e 'map(.name) | length == (unique | length)' "$LINKS"
}

@test "type matches source kind" {
  jq -er '.[] | [.source, .type] | @tsv' "$LINKS" > "$TMP/kinds"
  while IFS=$'\t' read -r source kind; do
    case "$kind" in
      dir) [ -d "$REPO/$source" ] ;;
      file) [ -f "$REPO/$source" ] && [ ! -d "$REPO/$source" ] ;;
      *) return 1 ;;
    esac
  done < "$TMP/kinds"
}

@test "karabiner backups ignored" {
  git -C "$REPO" check-ignore -q config/karabiner/automatic_backups/x.json
}

@test "weather env ignored" {
  git -C "$REPO" check-ignore -q config/sketchybar/scripts/weather.env.sh
}

@test "secrets targets are gitignored or outside config/" {
  jq -er '.[].target' "$REPO/manifest/secrets.json" > "$TMP/targets"
  while IFS= read -r target; do
    source=$(jq -r --arg target "$target" '
      .[] | . as $link |
      select($target == $link.target or
        ($link.type == "dir" and ($target | startswith($link.target + "/")))) |
      $link.source + ($target | ltrimstr($link.target))' "$LINKS")
    case "${source:-$target}" in
      config/*) git -C "$REPO" check-ignore -q "${source:-$target}" ;;
    esac
  done < "$TMP/targets"
}

@test "homebrew manifest contains the approved seed packages" {
  jq -e '
    .taps == [] and .brews == ["tpm"] and .casks == [
      "spotify", "arc", "todoist", "obsidian", "clay", "notion-calendar",
      "raindropio", "visual-studio-code", "mos", "mac-mouse-fix@2",
      "betterdisplay", "alt-tab", "logi-options+", "raycast", "karabiner-elements",
      "font-martian-mono-nerd-font", "font-hack-nerd-font", "1password", "1password-cli"
    ]' "$REPO/manifest/homebrew.json"
}

@test "nix manifest contains the approved attribute names" {
  jq -e '. == [
    "aerospace", "sketchybar", "jankyborders", "ghostty-bin", "neovim", "tmux",
    "ripgrep", "fd", "fzf", "zoxide", "thefuck", "vivid", "git", "git-town", "gh",
    "jq", "gitleaks", "python3", "lua-language-server", "typescript-language-server",
    "vscode-langservers-extracted", "stylua"
  ]' "$REPO/manifest/nix-packages.json"
}

@test "secrets manifest declares only the weather reference" {
  jq -e '. == [{"name":"weather", "op_ref":"op://smm/sketchybar-weather/env",
    "target":".config/sketchybar/scripts/weather.env.sh"}]' "$REPO/manifest/secrets.json"
}
