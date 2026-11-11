# Append /etc/paths and /etc/paths.d entries (cryptexes, XQuartz, IT-managed
# tools) like path_helper does, but after Nix's paths instead of before them.
__smm_etc_paths() {
  find "$1/paths" "$1/paths.d" -type f 2>/dev/null | sort | while IFS= read -r __smm_file; do
    while IFS= read -r __smm_dir || [ -n "$__smm_dir" ]; do
      case "$__smm_dir" in ''|'#'*) continue ;; esac
      printf '%s\n' "$__smm_dir"
    done < "$__smm_file"
  done
}
# Split on newlines only; the loop must run in this shell to change PATH.
__smm_ifs=$IFS
IFS='
'
for __smm_dir in $(__smm_etc_paths "${__smm_etc_root:-/etc}"); do
  case ":$PATH:" in *":$__smm_dir:"*) ;; *) PATH="$PATH:$__smm_dir" ;; esac
done
IFS=$__smm_ifs
export PATH
unset -f __smm_etc_paths
unset __smm_dir __smm_ifs
