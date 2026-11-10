#!/usr/bin/env bash

smm_validate() {
  local root=$1 name validator source result first failed=0 selected candidate
  shift
  export SMM_FAILED_LINKS=''
  local entries
  entries=$(jq -r '.[] | select(.validator != null) | [.name,.validator,.source] | @tsv' "$root/manifest/links.json") || return 1
  while IFS=$'\t' read -r name validator source; do
    [ -n "$name" ] || continue
    selected=0
    [ "$#" -eq 0 ] && selected=1
    for candidate in "$@"; do [ "$candidate" != "$name" ] || selected=1; done
    [ "$selected" -eq 1 ] || continue
    if declare -F "validate_$validator" >/dev/null; then
      if result=$("validate_$validator" "$root/$source" 2>&1); then
        if [[ "$result" == skipped* ]]; then printf '%s: %s\n' "$name" "$result";
        else printf 'ok %s\n' "$name"; fi
        continue
      fi
    else
      result="unknown validator: $validator"
    fi
    first=${result%%$'\n'*}
    printf 'fail %s: %s\n' "$name" "${first:-validator failed}"
    SMM_FAILED_LINKS="${SMM_FAILED_LINKS:+$SMM_FAILED_LINKS }$name"
    failed=1
  done <<< "$entries"
  return "$failed"
}

# A subshell keeps traps and temporary state out of the caller.
validate_aerospace() (
  if [ "${SMM_SKIP_AEROSPACE:-0}" = 1 ]; then
    echo 'skipped (checked with running server before and after activation)'; exit 0
  fi
  if ! pgrep -x AeroSpace >/dev/null; then
    echo 'skipped (aerospace not running)'; exit 0
  fi
  file=$1 live="$HOME/.aerospace.toml" state='' swap='' child=''
  if [ "$live" -ef "$file" ]; then
    aerospace reload-config --dry-run --no-gui
    exit "$?"
  fi
  file=$(cd "$(dirname "$file")" && printf '%s/%s\n' "$PWD" "$(basename "$file")") || exit 1
  state=$(smm_state_dir) || exit 1
  swap="$state/aerospace.swap"
  mkdir "$state/aerospace.lock" 2>/dev/null || { warn 'AeroSpace validation already in progress'; exit 1; }
  if [ -e "$swap" ] || [ -L "$swap" ]; then
    rmdir "$state/aerospace.lock"
    warn "restore existing AeroSpace backup first: $swap"
    exit 1
  fi
  aerospace_restore() {
    if [ -n "$child" ]; then kill -TERM "$child" 2>/dev/null || :; wait "$child" 2>/dev/null || :; child=''; fi
    # Inspect the filesystem: a signal may arrive after mv/ln completes but
    # before the next shell assignment could record that it completed.
    if [ -e "$swap" ] || [ -L "$swap" ]; then
      rm -f "$live"
      mv "$swap" "$live" || return
    elif [ -L "$live" ] && [ "$(readlink "$live")" = "$file" ]; then
      rm -f "$live"
    fi
    rmdir "$state/aerospace.lock" 2>/dev/null || :
  }
  trap aerospace_restore RETURN EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  if [ -e "$live" ] || [ -L "$live" ]; then
    mv "$live" "$swap" || exit 1
  fi
  ln -s "$file" "$live" || exit 1
  aerospace reload-config --dry-run --no-gui &
  child=$!
  status=0
  wait "$child" || status=$?
  child=''
  aerospace_restore
  exit "$status"
)
validate_ghostty() { ghostty +validate-config "--config-file=$1/config"; }
validate_karabiner() (
  dir=$1 tmp='' profile='' status=0 cli=''
  jq empty "$dir/karabiner.json" || exit 1
  # karabiner_cli ships inside the app's support folder, not on PATH
  cli=$(command -v karabiner_cli) ||
    cli="/Library/Application Support/org.pqrs/Karabiner-Elements/bin/karabiner_cli"
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  jq -c '.profiles[] | {title:"smm", rules:(.complex_modifications.rules // [])}' "$dir/karabiner.json" > "$tmp/profiles" || exit 1
  while IFS= read -r profile; do
    printf '%s\n' "$profile" > "$tmp/rules.json"
    "$cli" --lint-complex-modifications "$tmp/rules.json" || { status=$?; break; }
  done < "$tmp/profiles"
  exit "$status"
)
validate_sketchybar() {
  local dir=$1 file status=0
  bash -n "$dir/sketchybarrc" || status=1
  while IFS= read -r -d '' file; do
    bash -n "$file" || status=1
  done < <(find "$dir" -type f -name '*.sh' -print0)
  return "$status"
}
validate_tmux() { tmux -L smm-validate -f /dev/null start-server \; source-file -n "$1" \; kill-server; }
validate_zsh() { zsh -n "$1"; }
validate_plist() { plutil -lint "$1"; }
validate_nvim() (
  dir=$1 tmp='' status=0
  dir=$(cd "$dir" && pwd) || exit 1
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  mkdir "$tmp/config"
  ln -s "$dir" "$tmp/config/nvim" || exit 1
  XDG_CONFIG_HOME="$tmp/config" nvim --headless "+lua vim.defer_fn(function() if vim.v.errmsg ~= '' then vim.cmd('cq') else vim.cmd('qa') end end, 2000)" 2> "$tmp/stderr" || status=$?
  cat "$tmp/stderr" >&2
  if grep -Eq 'E[0-9]+:|Error' "$tmp/stderr"; then status=1; fi
  exit "$status"
)
