#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo" SMM_HOST=Ethans-MacBook-Pro-Mercury SMM_NIX_ROOT="$TMP/nix"
  mkdir -p "$SMM_NIX_ROOT" "$SMM_REPO/manifest"
  echo '{"Ethans-MacBook-Pro":{"nix":"determinate"},"Ethans-MacBook-Pro-Mercury":{"nix":"lix"}}' > "$SMM_REPO/manifest/hosts.json"
  for file in "$REPO"/smm/lib/*.sh; do source "$file"; done
  # Keep missing-Nix cases isolated even on a machine with a real installation.
  command() {
    if [ "$*" = '-v nix' ]; then [ -x "$TMP/bin/nix" ]; else builtin command "$@"; fi
  }
  choose() { echo unexpected-choice >> "$TMP/calls.log"; return 99; }
  stub_nix 'nix (Lix, like Nix) 2.95.2'
}
stub_nix() {
  stub nix 0
  printf '%s\n' "$1" > "$TMP/version"
  printf '%s\n' "${2:-0}" > "$TMP/daemon-status"
  sed_inplace '/exit 0/i\
case "$3" in\
  --version) cat "$TMP/version" ;;\
  store) exit "$(cat "$TMP/daemon-status")" ;;\
esac\
' "$TMP/bin/nix"
}
stub_repair() {
  stub "$1" "${2:-0}"
  sed_inplace '/exit /i\
printf "0\\n" > "$TMP/daemon-status"\
' "$TMP/bin/$1"
  cp "$TMP/bin/$1" "$SMM_NIX_ROOT/$1"
}
stub_download() {
  cp "$TMP/bin/nix" "$TMP/next-nix"
  rm "$TMP/bin/nix"
  curl() {
    echo "curl $*" >> "$TMP/calls.log"
    while [ "$#" -gt 0 ]; do
      if [ "$1" = -o ]; then
        printf '%s\n' 'echo "installer $*" >> "$TMP/calls.log"' \
          'cp "$TMP/next-nix" "$TMP/bin/nix"' > "$2"
        printf '%s\n' "$2" > "$TMP/download-path"
        return 0
      fi
      shift
    done
    return 1
  }
}
@test "smm_nix adds feature flags and preserves argument boundaries" {
  stub nix 0
  sed_inplace '/exit 0/i\
[ "$#" -eq 5 ] && [ "$2" = "nix-command flakes" ] && [ "$5" = "a path" ] || exit 98\
' "$TMP/bin/nix"
  run smm_nix eval --raw 'a path'
  [ "$status" -eq 0 ]
  calls | grep -qx 'nix --extra-experimental-features nix-command flakes eval --raw a path'
}
@test "sudo nix uses the same feature helper" {
  stub sudo 0
  run smm_nix --sudo run example -- switch
  [ "$status" -eq 0 ]
  calls | grep -qx 'sudo nix --extra-experimental-features nix-command flakes run example -- switch'
}
@test "host implementation follows smm_host and defaults unknown hosts to determinate" {
  run smm_nix_impl; [ "$status" -eq 0 ]; [ "$output" = lix ]
  SMM_HOST=Ethans-MacBook-Pro
  run smm_nix_impl; [ "$status" -eq 0 ]; [ "$output" = determinate ]
  unset SMM_HOST
  stub scutil 0 Ethans-MacBook-Pro-Mercury
  run smm_nix_impl; [ "$status" -eq 0 ]; [ "$output" = lix ]
  stub scutil 0 Unknown-Mac
  run smm_nix_impl; [ "$status" -eq 0 ]; [ "$output" = determinate ]
}
@test "done requires a working version matching the host and a responsive daemon" {
  run step_nix_done; [ "$status" -eq 0 ]
  calls | grep -qx 'nix --extra-experimental-features nix-command flakes store ping --store daemon'
  echo 1 > "$TMP/daemon-status"
  run step_nix_done; [ "$status" -ne 0 ]
  stub_nix 'nix (Determinate Nix) 3'
  run step_nix_done; [ "$status" -ne 0 ]
  SMM_HOST=Ethans-MacBook-Pro
  run step_nix_done; [ "$status" -eq 0 ]
  stub_nix 'nix (Lix, like Nix) 2.95.2'
  run step_nix_done; [ "$status" -ne 0 ]
  stub nix 1 'Lix'
  run step_nix_done; [ "$status" -ne 0 ]
}
@test "healthy Lix needs no prompt or choice state" {
  stub_repair nix-installer
  run step_nix_run; [ "$status" -eq 0 ]
  ! calls | grep -Eq 'repair|curl|uninstall|unexpected-choice|profile list|nix-env'
  [ -z "$(find "$SMM_STATE" -type f -print)" ]
}
@test "Lix on a determinate host stops without mutation even with both installers" {
  SMM_HOST=Ethans-MacBook-Pro
  stub_repair nix-installer; stub_repair lix-installer
  run step_nix_run
  [ "$status" -ne 0 ]; [[ "$output" == *Lix*determinate* ]]; [[ "$output" == *'never switches'* ]]
  ! calls | grep -Eq 'repair|curl|uninstall|unexpected-choice'
}
@test "Determinate and CppNix on a lix host stop without mutation" {
  stub_repair lix-installer; stub_repair nix-installer
  for version in 'nix (Determinate Nix) 3' 'nix (Nix) 2.31.2'; do
    stub_nix "$version"
    run step_nix_run
    [ "$status" -ne 0 ]; [[ "$output" == *lix* ]]; [[ "$output" == *'never switches'* ]]
  done
  ! calls | grep -Eq 'repair|curl|uninstall|unexpected-choice'
}
@test "unhealthy Lix uses only the Lix repair installer" {
  stub_nix 'nix (Lix, like Nix) 2.95.2' 1
  stub_repair nix-installer; stub_repair lix-installer
  run step_nix_run; [ "$status" -eq 0 ]
  calls | grep -qx 'lix-installer repair'
  ! calls | grep -Eq '^nix-installer|curl|uninstall'
}
@test "unhealthy Lix without its installer stops with repair instructions" {
  stub_nix 'nix (Lix, like Nix) 2.95.2' 1
  stub_repair nix-installer
  run step_nix_run
  [ "$status" -ne 0 ]; [[ "$output" == *Lix*repair* ]]
  ! calls | grep -Eq '^nix-installer|curl|uninstall'
}
@test "failed repair or persistently unhealthy daemon does not complete setup" {
  stub_nix 'Lix 2.95.2' 1
  stub_repair lix-installer 1
  run step_nix_run; [ "$status" -ne 0 ]
  stub lix-installer 0
  cp "$TMP/bin/lix-installer" "$SMM_NIX_ROOT/lix-installer"
  echo 1 > "$TMP/daemon-status"
  run step_nix_run; [ "$status" -ne 0 ]
}
@test "unhealthy determinate uses its existing repair installer" {
  SMM_HOST=Ethans-MacBook-Pro
  stub_nix 'nix (Determinate Nix) 3' 1
  stub_repair nix-installer; stub_repair lix-installer
  run step_nix_run; [ "$status" -eq 0 ]
  calls | grep -qx 'nix-installer repair'
  ! calls | grep -Eq '^lix-installer|curl|uninstall'
}
@test "missing Nix downloads the host installer runs install and cleans up" {
  for impl in lix determinate; do
    if [ "$impl" = lix ]; then
      SMM_HOST=Ethans-MacBook-Pro-Mercury
      stub_nix 'Lix 2.95.2'
      url=https://install.lix.systems/lix
    else
      SMM_HOST=Ethans-MacBook-Pro
      stub_nix 'nix (Determinate Nix) 3'
      url=https://install.determinate.systems/nix
    fi
    stub_download
    run step_nix_run; [ "$status" -eq 0 ]
    calls | grep -Fq "$url"
    calls | grep -qx 'installer install'
    [ ! -e "$(cat "$TMP/download-path")" ]
    : > "$TMP/calls.log"
  done
}
@test "a failed download never runs an installer" {
  for SMM_HOST in Ethans-MacBook-Pro-Mercury Ethans-MacBook-Pro; do
    rm -f "$TMP/bin/nix"
    stub curl 1
    run step_nix_run; [ "$status" -ne 0 ]
    ! calls | grep -Eq 'installer install|uninstall'
  done
}
@test "installer success still requires the expected implementation" {
  stub_nix 'nix (Determinate Nix) 3'
  stub_download
  run step_nix_run; [ "$status" -ne 0 ]
}

@test "unidentifiable existing Nix stops without risking an implementation change" {
  stub nix 1
  stub_repair nix-installer; stub_repair lix-installer
  run step_nix_run
  [ "$status" -ne 0 ]; [[ "$output" == *'Cannot identify'*'repair'* ]]
  ! calls | grep -Eq 'repair|curl|uninstall'
}
@test "determinate repair remains available when the CLI is missing" {
  SMM_HOST=Ethans-MacBook-Pro
  stub_nix 'nix (Determinate Nix) 3'
  cp "$TMP/bin/nix" "$TMP/next-nix"
  rm "$TMP/bin/nix"
  stub_repair nix-installer
  sed_inplace '/exit 0/i\
cp "$TMP/next-nix" "$TMP/bin/nix"\
' "$SMM_NIX_ROOT/nix-installer"
  run step_nix_run; [ "$status" -eq 0 ]
  calls | grep -qx 'nix-installer repair'
  ! calls | grep -Eq 'curl|uninstall'
}
