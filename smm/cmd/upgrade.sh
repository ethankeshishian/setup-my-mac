#!/usr/bin/env bash

# Always operate on the managed config, even before home-manager has linked it.
smm_nvim_run() (
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  ln -s "$(smm_repo)/config/nvim" "$tmp/nvim" || exit 1
  XDG_CONFIG_HOME="$tmp" nvim --headless "$@" +qa
)

smm_upgrade_reviews() (
  repo=$(smm_repo)
  if [ -f "$repo/manifest/nvchad-starter.json" ]; then
    upstream=$(jq -er .upstream "$repo/manifest/nvchad-starter.json") || exit 1
    branch=$(jq -er .branch "$repo/manifest/nvchad-starter.json") || exit 1
    merged=$(jq -er .merged "$repo/manifest/nvchad-starter.json") || exit 1
    latest=$(git ls-remote "$upstream" "refs/heads/$branch" | awk 'NR==1 {print $1}') || exit 1
    if [ -n "$latest" ] && [ "$latest" != "$merged" ]; then
      tmp=$(mktemp -d) || exit 1
      trap 'rm -rf "$tmp"' EXIT
      git init -q "$tmp" || exit 1
      git -C "$tmp" fetch -q "$upstream" "$branch" || exit 1
      log 'NvChad starter: review only, not applied'
      git -C "$tmp" log --oneline --stat "$merged..FETCH_HEAD" || exit 1
    fi
  fi
  current=$(sed -n 's/.*branch *= *"\(v[0-9.]*\)".*/\1/p' "$repo/config/nvim/init.lua" 2>/dev/null | head -n 1)
  heads=$(git ls-remote --heads https://github.com/NvChad/NvChad 'v*') || exit 1
  [ -n "$current" ] || exit 0
  awk -v current="${current#v}" '
    function higher(a,b, x,y,n,nx,i) {
      nx=split(a,x,"."); n=split(b,y,".");
      for(i=1;i<=n || i<=nx;i++) {if(x[i]+0>y[i]+0)return 1; if(x[i]+0<y[i]+0)return 0} return 0
    }
    {sub("refs/heads/v", "", $2); if ($2 ~ /^[0-9.]+$/ && higher($2,current)) print "NvChad branch available: v" $2 " (review only, not applied)"}
  ' <<< "$heads"
)

smm_upgrade_diff() {
  local kind=$1 old=$2 new=$3
  jq -nr --arg kind "$kind" --slurpfile old "$old" --slurpfile new "$new" '
    (if $kind == "input" then $old[0].nodes else $old[0] end) as $a |
    (if $kind == "input" then $new[0].nodes else $new[0] end) as $b |
    (($a|keys) + ($b|keys) | unique)[] as $k |
    (if $kind == "input" then $a[$k].locked else $a[$k].commit end) as $x |
    (if $kind == "input" then $b[$k].locked else $b[$k].commit end) as $y |
    select($x != $y) |
    "\($kind) \($k) \(if $kind == "input" then ($x.rev // $x.narHash // "missing") else ($x // "missing") end) → \(if $kind == "input" then ($y.rev // $y.narHash // "missing") else ($y // "missing") end)"'
}

cmd_upgrade() (
  case "${1:-}" in -y) export SMM_YES=1; shift ;; esac
  [ "$#" -eq 0 ] || { warn 'usage: smm upgrade [-y]'; exit 2; }
  repo=$(smm_repo)
  cd "$repo" || exit 1
  [ -z "$(git status --porcelain)" ] || { warn 'commit or sync first'; exit 1; }
  tmp=$(mktemp -d) || exit 1
  complete=0 switched=0 prev='' casks='' original_path=$PATH
  # shellcheck disable=SC2329
  smm_upgrade_cleanup() {
    if [ "$complete" -eq 0 ]; then
      export PATH="$original_path"
      if [ "$switched" -eq 1 ]; then smm_rollback "$prev" || warn 'rollback failed'; fi
      cp "$tmp/flake.lock" "$repo/flake.lock" || :
      cp "$tmp/lazy-lock.json" "$repo/config/nvim/lazy-lock.json" || :
      smm_nvim_run '+Lazy! restore' || warn 'plugin restore failed'
      if [ "$switched" -eq 1 ]; then smm_reload || :; fi
    fi
    rm -rf "$tmp"
  }
  if ! cp flake.lock "$tmp/flake.lock" || ! cp config/nvim/lazy-lock.json "$tmp/lazy-lock.json"; then
    rm -rf "$tmp"; exit 1
  fi
  trap smm_upgrade_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  smm_nix flake update || exit 1
  smm_nvim_run '+Lazy! update' && validate_nvim "$repo/config/nvim" || exit 1
  smm_upgrade_reviews || exit 1
  prev=$(smm_generation) || exit 1
  smm_build && smm_use_build_tools && smm_run_validate "$repo" || exit 1
  switched=1
  smm_switch || exit 1
  smm_validate_prefs "$repo" || exit 1
  if ! smm_health; then
    if [ "$(smm_health_reason aerospace)" = no-accessibility ]; then
      smm_wait_permission aerospace && smm_health || exit 1
    else exit 1; fi
  fi
  outdated=$(brew outdated --cask --json) || exit 1
  names=$(jq -er 'if (.casks | type) != "array" then error("missing cask list")
    else [.casks[].name] | join("\n") end' <<< "$outdated") || exit 1
  if [ -n "$names" ]; then
    printf 'Homebrew updates (cannot be undone):\n%s\n' "$outdated"
    if confirm "Upgrade these? This can't be undone."; then
      args=()
      while IFS= read -r name; do args+=("$name"); done <<< "$names"
      brew upgrade --cask "${args[@]}" || exit 1
      casks=$(printf '%s' "$names" | tr '\n' ' ')
      smm_run_validate "$repo" karabiner && smm_health || exit 1
    fi
  fi
  smm_upgrade_diff input "$tmp/flake.lock" flake.lock > "$tmp/inputs" || exit 1
  smm_upgrade_diff plugin "$tmp/lazy-lock.json" config/nvim/lazy-lock.json > "$tmp/plugins" || exit 1
  n=$(awk 'END {print NR+0}' "$tmp/inputs")
  m=$(awk 'END {print NR+0}' "$tmp/plugins")
  {
    printf 'upgrade: %s inputs, %s plugins\n\n' "$n" "$m"
    cat "$tmp/inputs" "$tmp/plugins"
    [ -z "$casks" ] || printf 'casks: %s\n' "$casks"
  } > "$tmp/message"
  if ! git diff --quiet -- flake.lock config/nvim/lazy-lock.json || [ -n "$casks" ]; then
    git add -- flake.lock config/nvim/lazy-lock.json && git commit --allow-empty -F "$tmp/message" || exit 1
  fi
  smm_finalize_apply || exit 1
  complete=1
  cat "$tmp/message"
)
