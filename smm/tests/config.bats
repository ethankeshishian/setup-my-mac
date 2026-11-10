#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}
@test "AeroSpace v2 keeps eight workspaces without starting managed services" {
  python3 - "$REPO/config/.aerospace.toml" <<'PY'
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
    config = tomllib.load(f)
assert config['config-version'] == 2
assert config['persistent-workspaces'] == [str(i) for i in range(1, 9)]
assert config['after-startup-command'] == []
assert config['start-at-login'] is False
assert 'aerospace_workspace_change' in ' '.join(config['exec-on-workspace-change'])
PY
}
@test "Ghostty uses the approved Catppuccin theme" {
  run rg '^theme = Catppuccin Mocha$' "$REPO/config/ghostty/config"
  [ "$status" -eq 0 ]
}
@test "nvim disables Mason PATH changes and keeps Haskell on the ghcup PATH" {
  rg '"williamboman/mason.nvim"' "$REPO/config/nvim/lua/plugins/init.lua"
  rg 'PATH = "skip"' "$REPO/config/nvim/lua/plugins/init.lua"
  rg 'ensure_installed = \{\}' "$REPO/config/nvim/lua/plugins/init.lua"
  rg 'cmd = \{ "static-ls" \}' "$REPO/config/nvim/lua/configs/lspconfig.lua"
  rg '"command": "static-ls"' "$REPO/config/nvim/coc-settings.json"
  jq -e 'index("haskellPackages.static-ls") == null' "$REPO/manifest/nix-packages.json"
}

@test "shared zsh keeps the fuck alias with pay-respects" {
  rg -Fx 'eval "$(pay-respects zsh --alias fuck)"' "$REPO/config/zsh/common.zsh"
}
