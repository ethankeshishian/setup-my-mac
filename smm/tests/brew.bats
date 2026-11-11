#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo"
  mkdir -p "$SMM_REPO/manifest"
  printf '%s\n' '{"taps":["owner/repo"],"brews":["tpm"],"casks":["arc"]}' > "$SMM_REPO/manifest/homebrew.json"
  source "$REPO/smm/lib/common.sh"
  source "$REPO/smm/lib/brew.sh"
  stub brew 0 $'Would uninstall formulae:\n  wget\nWould uninstall casks:\n  kitty\nWould untap:\n  owner/extra'
}
@test "brewfile declares manifest packages" {
  file=$(smm_brewfile)
  [ "$file" = "$SMM_STATE/Brewfile" ]
  grep -qx 'tap "owner/repo"' "$file"
  grep -qx 'brew "tpm"' "$file"
  grep -qx 'cask "arc"' "$file"
}
@test "undeclared parsed from cleanup output" {
  run smm_brew_undeclared
  [ "$status" -eq 0 ]
  [ "$output" = $'brew wget\ncask kitty\ntap owner/extra' ]
  calls | grep -qx "brew bundle cleanup --file=$SMM_STATE/Brewfile"
}
@test "add writes manifest sorted and deduplicated" {
  smm_brew_add brew zstd
  smm_brew_add brew aaa
  smm_brew_add brew tpm
  jq -e '.brews == ["aaa","tpm","zstd"]' "$SMM_REPO/manifest/homebrew.json"
}
@test "remove calls brew uninstall cask and untap for taps" {
  # Override only the terminal predicate, retaining the safe noninteractive default.
  smm_brew_interactive() { return 0; }
  choose() { printf 'remove\n'; }
  smm_brew_resolve
  calls | grep -qx 'brew uninstall --cask kitty'
  calls | grep -qx 'brew uninstall wget'
  calls | grep -qx 'brew untap owner/extra'
}
@test "interactive add updates manifest" {
  smm_brew_interactive() { return 0; }
  choose() { printf 'add to setup\n'; }
  smm_brew_resolve
  jq -e '.brews == ["tpm","wget"] and .casks == ["arc","kitty"]' "$SMM_REPO/manifest/homebrew.json"
  ! calls | grep -q uninstall
}
@test "non-interactive never uninstalls even with yes" {
  choose() { return 99; }
  smm_brew_resolve
  SMM_YES=1 smm_brew_resolve
  ! calls | grep -Eq 'uninstall|untap'
}
@test "list-only never prompts or uninstalls" {
  choose() { return 99; }
  run smm_brew_resolve --list-only
  [ "$status" -eq 0 ]
  [[ "$output" == *'cask kitty'* ]]
  ! calls | grep -Eq 'uninstall|untap'
}
@test "cleanup failure is not treated as no drift" {
  stub brew 2 'brew failed'
  run smm_brew_undeclared
  [ "$status" -ne 0 ]
}

@test "cleanup drift exit 1 and multiple columns are parsed without prompting" {
  stub brew 1 $'Would uninstall casks:\nkitty  firefox\nWould uninstall formulae:\nwget zstd\nRun `brew bundle cleanup --force` to make these changes.'
  run smm_brew_undeclared
  [ "$status" -eq 0 ]
  [ "$output" = $'cask kitty\ncask firefox\nbrew wget\nbrew zstd' ]
}

# brew stub that answers list, info and install the way real brew does.
stub_cask_brew() {
  cat > "$TMP/bin/brew" <<'STUB'
#!/usr/bin/env bash
printf 'brew %s\n' "$*" >> "$TMP/calls.log"
case "$1" in
  list) printf 'kitty\n' ;;
  info)
    case "$4" in
      arc) printf '%s\n' '{"casks":[{"artifacts":[{"uninstall":[{}]},{"app":["Arc.app"]}]}]}' ;;
      mos) printf '%s\n' '{"casks":[{"artifacts":[{"app":["Mos.app",{"target":"Mos Renamed.app"}]}]}]}' ;;
      broken) exit 1 ;;
      *) printf '%s\n' '{"casks":[{"artifacts":[{"installer":[{}]}]}]}' ;;
    esac ;;
  install) [ "$3" = --adopt ] && [ "$4" = mos ] && exit 1; exit 0 ;;
esac
STUB
  chmod +x "$TMP/bin/brew"
  printf '%s\n' '{"taps":[],"brews":[],"casks":["arc","broken","kitty","logi","mos"]}' > "$SMM_REPO/manifest/homebrew.json"
  mkdir -p "$SMM_APPLICATIONS_DIR/Arc.app" "$SMM_APPLICATIONS_DIR/Mos Renamed.app" "$SMM_APPLICATIONS_DIR/Kitty.app"
}
@test "unmanaged casks are declared apps already installed outside Homebrew" {
  stub_cask_brew
  run smm_brew_unmanaged_casks
  [ "$status" -eq 0 ]
  # kitty is Homebrew's already, logi installs no app, broken is unknown to brew info.
  [ "$output" = $'arc\tArc.app\nmos\tMos Renamed.app' ]
}
@test "matching unmanaged app is adopted without replacing it" {
  stub_cask_brew
  printf '%s\n' '{"taps":[],"brews":[],"casks":["arc"]}' > "$SMM_REPO/manifest/homebrew.json"
  smm_brew_adopt_unmanaged
  calls | grep -qx 'brew install --cask --adopt arc'
  ! calls | grep -q -- '--force'
}
@test "differing unmanaged app is never replaced without asking" {
  stub_cask_brew
  choose() { return 99; }
  run smm_brew_adopt_unmanaged
  [ "$status" -eq 1 ]
  [[ "$output" == *'Mos Renamed.app differs from the mos cask'* ]]
  calls | grep -qx 'brew install --cask --adopt arc'
  ! calls | grep -q -- '--force'
}
@test "differing unmanaged app is replaced only when chosen" {
  stub_cask_brew
  smm_brew_interactive() { return 0; }
  choose() { printf 'stop setup\n'; }
  run smm_brew_adopt_unmanaged
  [ "$status" -eq 1 ]
  ! calls | grep -q -- '--force'
  choose() { printf 'replace it with the Homebrew version\n'; }
  smm_brew_adopt_unmanaged
  calls | grep -qx 'brew install --cask --force mos'
}
