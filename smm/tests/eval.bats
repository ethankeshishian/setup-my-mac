#!/usr/bin/env bats

load helpers

setup_file() {
  setup_tmp
  local repo
  repo="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  # Remove only this helper's Nix stub; every other system tool stays stubbed.
  rm -f "$TMP/bin/nix"
  if ! command -v nix >/dev/null 2>&1; then
    touch "$BATS_FILE_TMPDIR/nix-missing"
    return 0
  fi
  cd "$repo" || return 1
  # Project only the values under test: never serialize entire configurations
  # or realize the out-of-store symlink derivations.
  # shellcheck disable=SC2016 # ${host} is Nix interpolation, not shell expansion.
  if ! nix --extra-experimental-features 'nix-command flakes' eval --json --impure \
    --expr "builtins.getFlake \"git+file://$repo\"" --apply '
    flake: {
      hosts = builtins.listToAttrs (map (host:
        let
          c = flake.darwinConfigurations.${host}.config;
          files = c.home-manager.users.ethankeshishian.home.file;
        in {
          name = host;
          value = {
            nixEnabled = c.nix.enable;
            dockOrientation = c.system.defaults.dock.orientation;
            dockExposeGroupApps = c.system.defaults.dock.expose-group-apps;
            homebrewCasks = map (cask: cask.name) c.homebrew.casks;
            homebrewActivation = {
              inherit (c.homebrew.onActivation) cleanup autoUpdate upgrade;
            };
            borders = {
              inherit (c.services.jankyborders) active_color inactive_color width;
            };
            sketchybarPackages = map
              (p: p.pname or (builtins.parseDrvName p.name).name)
              c.services.sketchybar.extraPackages;
            sketchybarConfig = c.services.sketchybar.config;
            localHostName = c.networking.localHostName;
            awsCaBundle = c.environment.variables.AWS_CA_BUNDLE or null;
            extraInit = c.environment.extraInit;
            aerospaceEnabled = c.services.aerospace.enable;
            aerospaceService = c.launchd.user.agents.aerospace.serviceConfig;
            aerospacePath = c.launchd.user.agents.aerospace.path;
            symbolicHotkeys = c.system.defaults.CustomUserPreferences."com.apple.symbolichotkeys".AppleSymbolicHotKeys;
            aerospaceLinkCommand = files.".aerospace.toml".source.buildCommand;
            homeFileNames = builtins.attrNames files;
            karabinerRecursive = files.".config/karabiner".recursive;
            backupFileExtension = c.home-manager.backupFileExtension;
            homeFilesUnforced = builtins.all (file: !file.force) (builtins.attrValues files);
            tmuxSource = toString files.".config/tmux/plugins/catppuccin/tmux".source;
            zshLinkCommand = files.".zshrc".source.buildCommand;
            altTabPrefs = c.system.defaults.CustomUserPreferences."com.lwouis.alt-tab-macos";
            altTabApp = map (p: p.version)
              (builtins.filter (p: (p.pname or "") == "alttab") c.environment.systemPackages);
            raycastPrefs = c.system.defaults.CustomUserPreferences."com.raycast.macos";
          };
        }) [ "Ethans-MacBook-Pro" "Ethans-MacBook-Pro-Mercury" ]);
      darwinRebuildName = flake.packages.aarch64-darwin.darwin-rebuild.name;
      darwinRebuildProgram = flake.apps.aarch64-darwin.darwin-rebuild.program;
    }
  ' > "$BATS_FILE_TMPDIR/eval.json" 2> "$BATS_FILE_TMPDIR/eval.error"; then
    # setup_file must succeed so setup can fail EACH test with the same error.
    touch "$BATS_FILE_TMPDIR/eval.failed"
  fi
}

setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  if [ -f "$BATS_FILE_TMPDIR/nix-missing" ]; then
    skip "nix not installed"
  fi
  if [ -f "$BATS_FILE_TMPDIR/eval.failed" ]; then
    cat "$BATS_FILE_TMPDIR/eval.error" >&2
    return 1
  fi
  HOST=Ethans-MacBook-Pro
}

eval_json() {
  run jq -c --arg host "$HOST" --arg p "$1" '
    .hosts[$host] | ($p | split(".")) as $k |
    if any(paths; . == $k) then getpath($k) else error("missing key: \($p)") end' "$BATS_FILE_TMPDIR/eval.json"
  [ "$status" -eq 0 ]
}

eval_raw() {
  run jq -r --arg host "$HOST" --arg p "$1" '
    .hosts[$host] | ($p | split(".")) as $k |
    if any(paths; . == $k) then getpath($k) else error("missing key: \($p)") end' "$BATS_FILE_TMPDIR/eval.json"
  [ "$status" -eq 0 ]
}

@test "host installers manage Nix on both Macs" {
  for host in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    HOST=$host
    eval_json nixEnabled
    [ "$output" = false ]
  done
}

@test "Dock is on the right" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_raw dockOrientation
    [ "$output" = right ]
  done
}

@test "Mission Control groups windows by app" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json dockExposeGroupApps
    [ "$output" = true ]
  done
}

@test "Homebrew declares Arc and Karabiner without nightly Ghostty" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json homebrewCasks
    jq -e 'index("arc") != null and index("karabiner-elements") != null and index("ghostty@tip") == null' <<< "$output"
  done
}

@test "Homebrew activation never removes undeclared packages" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_raw homebrewActivation.cleanup
    [ "$output" = none ]
  done
}

@test "Homebrew activation never updates or upgrades packages" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json homebrewActivation.autoUpdate
    [ "$output" = false ]
    eval_json homebrewActivation.upgrade
    [ "$output" = false ]
  done
}

@test "Borders use the approved appearance" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_raw borders.active_color
    [ "$output" = 0xff3a6aff ]
    eval_raw borders.inactive_color
    [ "$output" = 0x00494d64 ]
    eval_json borders.width
    jq -e '. == 12' <<< "$output"
  done
}

@test "SketchyBar can call AeroSpace and jq under launchd" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json sketchybarPackages
    jq -e 'index("aerospace") != null and index("jq") != null' <<< "$output"
  done
}

@test "SketchyBar uses the linked config" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_raw sketchybarConfig
    [ -z "$output" ]
  done
}

@test "Mercury keeps the AWS CA bundle that nix-darwin's /etc files would drop" {
  HOST=Ethans-MacBook-Pro-Mercury
  eval_raw awsCaBundle
  [ "$output" = /Library/Mercury/certs/aws-ca-bundle.pem ]
  HOST=Ethans-MacBook-Pro
  eval_json awsCaBundle
  [ "$output" = null ]
}

@test "shell init appends /etc/paths entries after Nix paths on both Macs" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_raw extraInit
    [[ "$output" == *'__smm_etc_paths "${__smm_etc_root:-/etc}"'* ]] || return 1
  done
}
@test "host identity is fixed" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_raw localHostName
    [ "$output" = "$HOST" ]
  done
}

@test "AeroSpace generated config service stays disabled" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json aerospaceEnabled
    [ "$output" = false ]
  done
}

@test "AeroSpace starts the Nix application with the service tools on PATH" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json aerospaceService
    jq -e '.ProgramArguments == ["/Applications/Nix Apps/AeroSpace.app/Contents/MacOS/AeroSpace"] and .KeepAlive == true and .RunAtLoad == true' <<< "$output"
    eval_raw aerospacePath
    [[ "$output" == *sketchybar*/bin* ]]
  done
}

@test "symbolic hotkeys preserve the old parameter values" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json symbolicHotkeys
    jq -e '."64".enabled == false and ."65".enabled == false and
      ."64".value.parameters == [65535, 49, 1048576] and
      ."65".value.parameters == [65535, 49, 1572864] and
      ."64".type == "standard" and ."65".type == "standard"' <<< "$output"
  done
}

@test "aerospace link points into repo" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    # mkOutOfStoreSymlink returns a derivation, not the live target string.
    # Inspect its builder without realizing it or touching the real HOME.
    eval_raw aerospaceLinkCommand
    [[ "$output" == *'ln -s '* ]]
    [[ "$output" == *'/Users/ethankeshishian/Repos/setup-my-mac/config/.aerospace.toml'* ]]
  done
}

@test "karabiner linked as dir" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json homeFileNames
    jq -e 'index(".config/karabiner") != null and index(".config/karabiner/karabiner.json") == null' <<< "$output"
    eval_json karabinerRecursive
    [ "$output" = false ]
  done
}

@test "link count equals manifest count" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json homeFileNames
    jq -r '.[].target' "$REPO/manifest/links.json" | LC_ALL=C sort > "$TMP/expected"
    jq -r '.[] | select(startswith("/") | not) |
      select(. != "Library/Fonts/.home-manager-fonts-version" and
        . != ".config/tmux/plugins/catppuccin/tmux")' <<< "$output" | LC_ALL=C sort > "$TMP/actual"
    [ "$(wc -l < "$TMP/actual")" -eq "$(jq length "$REPO/manifest/links.json")" ]
    diff -u "$TMP/expected" "$TMP/actual"
  done
}

@test "home-manager never renames conflicting files" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json backupFileExtension
    [ "$output" = null ]
    eval_json homeFilesUnforced
    [ "$output" = true ]
  done
}

@test "flake exposes bootstrap darwin-rebuild package and app" {
  run jq -r '.darwinRebuildName' "$BATS_FILE_TMPDIR/eval.json"
  [ "$status" -eq 0 ]; [[ "$output" == *darwin-rebuild* ]]
  run jq -r '.darwinRebuildProgram' "$BATS_FILE_TMPDIR/eval.json"
  [ "$status" -eq 0 ]; [[ "$output" == */bin/darwin-rebuild ]]
}

@test "tmux Catppuccin comes from the pinned Nix package" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_raw tmuxSource
    [[ "$output" == /nix/store/*/share/tmux-plugins/catppuccin ]]
  done
}

@test "zsh source uses each darwin local host identity" {
  for host in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    HOST=$host
    eval_raw zshLinkCommand
    [[ "$output" == *"/config/zsh/$host.zshrc"* ]]
    [[ "$output" != *'{host}'* ]]
  done
}

@test "app preferences come from versioned manifests" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json altTabPrefs
    [ "$(jq -cS . <<< "$output")" = "$(jq -cS .keys "$REPO/manifest/prefs/com.lwouis.alt-tab-macos.json")" ]
    eval_json raycastPrefs
    [ "$(jq -cS . <<< "$output")" = '{"raycastGlobalHotkey":"Command-49"}' ]
  done
}

@test "evaluation helpers reject missing keys while accepting null and false" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    if eval_json absent.key; then return 1; fi
    [[ "$output" == *'missing key: absent.key'* ]]
    if eval_raw absent.key; then return 1; fi
    [[ "$output" == *'missing key: absent.key'* ]]
    eval_json backupFileExtension
    [ "$output" = null ]
    eval_json nixEnabled
    [ "$output" = false ]
  done
}

@test "AltTab 10.12.0 is installed by Nix on both Macs" {
  for HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    eval_json altTabApp
    [ "$output" = '["10.12.0"]' ]
  done
}
