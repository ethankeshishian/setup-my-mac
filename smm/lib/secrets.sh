#!/usr/bin/env bash

smm_secrets_materialize() (
  umask 077
  refresh=0 signed_in=0 tmp=''
  [ "${1:-}" != --refresh ] || refresh=1
  trap '[ -z "$tmp" ] || rm -f "$tmp"' EXIT
  entries=$(jq -r '.[] | [.name,.op_ref,.target] | @tsv' "$(smm_repo)/manifest/secrets.json") || exit 1
  while IFS=$'\t' read -r name ref target; do
    [ -n "$name" ] || continue
    case "/$target/" in *'/../'*|*'/./'*|//*) warn "$name: invalid secret target"; exit 1 ;; esac
    dest="$HOME/$target"
    if [ "$refresh" -eq 0 ] && [ -f "$dest" ]; then continue; fi
    if [ "$signed_in" -eq 0 ]; then
      if op whoami >/dev/null 2>&1; then signed_in=1; else signed_in=2; fi
    fi
    if [ "$signed_in" -eq 2 ]; then warn "$name: 1Password not signed in, skipping"; continue; fi
    mkdir -p "$(dirname "$dest")" || exit 1
    tmp=$(mktemp "$(dirname "$dest")/.smm-secret.XXXXXX") || exit 1
    if ! op read "$ref" > "$tmp" 2>/dev/null; then warn "$name: could not read 1Password secret"; exit 1; fi
    chmod 600 "$tmp" || exit 1
    mv -f "$tmp" "$dest" || exit 1
    tmp=''
  done <<< "$entries"
)
