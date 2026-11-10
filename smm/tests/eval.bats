#!/usr/bin/env bats

load helpers

setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  rm -f "$TMP/bin/nix"
  if ! command -v nix >/dev/null 2>&1; then
    skip "nix not installed"
  fi
  cd "$REPO" || return 1
  FLAKE='.#darwinConfigurations.Ethans-MacBook-Pro.config'
}

eval_json() {
  local path=$1
  shift
  run nix eval --json --no-write-lock-file "$FLAKE.$path" "$@"
  [ "$status" -eq 0 ]
}

eval_raw() {
  local path=$1
  shift
  run nix eval --raw --no-write-lock-file "$FLAKE.$path" "$@"
  [ "$status" -eq 0 ]
}

@test "host installers manage Nix on both Macs" {
  for host in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    FLAKE=".#darwinConfigurations.$host.config"
    eval_json nix.enable
    [ "$output" = false ]
  done
}

@test "Dock is on the right" {
  eval_raw system.defaults.dock.orientation
  [ "$output" = right ]
}

@test "Mission Control groups windows by app" {
  eval_json system.defaults.dock.expose-group-apps
  [ "$output" = true ]
}

@test "Homebrew declares Arc and Karabiner without nightly Ghostty" {
  eval_json homebrew.casks --apply 'casks: map (c: c.name) casks'
  jq -e 'index("arc") != null and index("karabiner-elements") != null and index("ghostty@tip") == null' <<< "$output"
}

@test "Homebrew activation never removes undeclared packages" {
  eval_raw homebrew.onActivation.cleanup
  [ "$output" = none ]
}

@test "Homebrew activation never updates or upgrades packages" {
  eval_json homebrew.onActivation.autoUpdate
  [ "$output" = false ]
  eval_json homebrew.onActivation.upgrade
  [ "$output" = false ]
}

@test "Borders use the approved appearance" {
  eval_raw services.jankyborders.active_color
  [ "$output" = 0xff3a6aff ]
  eval_raw services.jankyborders.inactive_color
  [ "$output" = 0x00494d64 ]
  eval_json services.jankyborders.width
  jq -e '. == 12' <<< "$output"
}

@test "SketchyBar can call AeroSpace and jq under launchd" {
  eval_json services.sketchybar.extraPackages --apply 'packages: map (p: p.pname or (builtins.parseDrvName p.name).name) packages'
  jq -e 'index("aerospace") != null and index("jq") != null' <<< "$output"
}

@test "SketchyBar uses the linked config" {
  eval_raw services.sketchybar.config
  [ -z "$output" ]
}

@test "host identity is fixed" {
  eval_raw networking.localHostName
  [ "$output" = Ethans-MacBook-Pro ]
}

@test "AeroSpace generated config service stays disabled" {
  eval_json services.aerospace.enable
  [ "$output" = false ]
}

@test "AeroSpace starts the Nix application with the service tools on PATH" {
  eval_json launchd.user.agents.aerospace.serviceConfig
  jq -e '.ProgramArguments == ["/Applications/Nix Apps/AeroSpace.app/Contents/MacOS/AeroSpace"] and .KeepAlive == true and .RunAtLoad == true' <<< "$output"
  eval_raw launchd.user.agents.aerospace.path
  [[ "$output" == *sketchybar*/bin* ]]
}

@test "symbolic hotkeys preserve the old parameter values" {
  eval_json 'system.defaults.CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys'
  jq -e '."64".enabled == false and ."65".enabled == false and
    ."64".value.parameters == [65535, 49, 1048576] and
    ."65".value.parameters == [65535, 49, 1572864] and
    ."64".type == "standard" and ."65".type == "standard"' <<< "$output"
}

@test "aerospace link points into repo" {
  # mkOutOfStoreSymlink returns a derivation, not the live target string.
  # Inspect its builder without realizing it or touching the real HOME.
  eval_raw 'home-manager.users.ethankeshishian.home.file.".aerospace.toml".source' \
    --apply 'source: source.buildCommand'
  [[ "$output" == *'ln -s '* ]]
  [[ "$output" == *'/Users/ethankeshishian/Repos/setup-my-mac/config/.aerospace.toml'* ]]
}

@test "karabiner linked as dir" {
  eval_json home-manager.users.ethankeshishian.home.file --apply builtins.attrNames
  jq -e 'index(".config/karabiner") != null and index(".config/karabiner/karabiner.json") == null' <<< "$output"
  eval_json 'home-manager.users.ethankeshishian.home.file.".config/karabiner".recursive'
  [ "$output" = false ]
}

@test "link count equals manifest count" {
  eval_json home-manager.users.ethankeshishian.home.file --apply builtins.attrNames
  [ "$(jq length <<< "$output")" -eq "$(($(jq length "$REPO/manifest/links.json") + 1))" ]
  jq -r '.[].target' "$REPO/manifest/links.json" | LC_ALL=C sort > "$TMP/expected"
  jq -r '.[] | select(. != ".config/tmux/plugins/catppuccin/tmux")' <<< "$output" | LC_ALL=C sort > "$TMP/actual"
  diff -u "$TMP/expected" "$TMP/actual"
}

@test "home-manager never renames conflicting files" {
  eval_json home-manager.backupFileExtension
  [ "$output" = null ]
  eval_json home-manager.users.ethankeshishian.home.file \
    --apply 'files: builtins.all (file: !file.force) (builtins.attrValues files)'
  [ "$output" = true ]
}

@test "flake exposes bootstrap darwin-rebuild package and app" {
  run nix eval --raw --no-write-lock-file '.#packages.aarch64-darwin.darwin-rebuild.name'
  [ "$status" -eq 0 ]; [[ "$output" == *darwin-rebuild* ]]
  run nix eval --raw --no-write-lock-file '.#apps.aarch64-darwin.darwin-rebuild.program'
  [ "$status" -eq 0 ]; [[ "$output" == */bin/darwin-rebuild ]]
}

@test "tmux Catppuccin comes from the pinned Nix package" {
  eval_raw 'home-manager.users.ethankeshishian.home.file.".config/tmux/plugins/catppuccin/tmux".source'
  [[ "$output" == /nix/store/*/share/tmux-plugins/catppuccin ]]
}

@test "zsh source uses each darwin local host identity" {
  for host in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    FLAKE=".#darwinConfigurations.$host.config"
    eval_raw 'home-manager.users.ethankeshishian.home.file.".zshrc".source' --apply 'source: source.buildCommand'
    [[ "$output" == *"/config/zsh/$host.zshrc"* ]]
    [[ "$output" != *'{host}'* ]]
  done
}

@test "app preferences come from versioned manifests" {
  eval_json 'system.defaults.CustomUserPreferences."com.lwouis.alt-tab-macos"'
  [ "$(jq -cS . <<< "$output")" = "$(jq -cS .keys "$REPO/manifest/prefs/com.lwouis.alt-tab-macos.json")" ]
  eval_json 'system.defaults.CustomUserPreferences."com.raycast.macos"'
  [ "$(jq -cS . <<< "$output")" = '{"raycastGlobalHotkey":"Command-49"}' ]
}
