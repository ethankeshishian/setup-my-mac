#!/usr/bin/env bash

cmd_raycast() (
  [ "$#" -eq 2 ] && [ "$1" = save ] || { warn 'usage: smm raycast save <file.rayconfig>'; exit 2; }
  requested=$(cd "$(dirname "$2")" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$2")") || exit 1
  file=$(readlink -f "$requested") || exit 1
  repo=$(cd "$(smm_repo)" && pwd -P) || exit 1
  for path in "$requested" "$file"; do
    case "$path" in "$repo"|"$repo"/*) warn 'refusing Raycast export inside the repo'; exit 1 ;; esac
  done
  case "$file" in *.rayconfig) ;; *) warn 'expected a .rayconfig file'; exit 1 ;; esac
  [ -f "$file" ] || { warn 'Raycast export file missing'; exit 1; }
  version=$(smm_app_version raycast) || { warn 'Raycast not installed or version unreadable'; exit 1; }
  op whoami >/dev/null 2>&1 || { warn '1Password not signed in'; exit 1; }
  result=0
  document=$(smm_raycast_document) || result=$?
  tags="smm-raycast-version:$version,smm-raycast-exported:$(date +%s)"
  case "$result" in
    0)
      id=$(jq -er .id <<< "$document") || exit 1
      op document edit "$id" "$file" --vault smm --title raycast-config --tags "$tags" >/dev/null || exit 1 ;;
    3)
      vault_status=0
      smm_raycast_vault_exists || vault_status=$?
      case "$vault_status" in
        0) ;;
        3) op vault create smm >/dev/null || exit 1 ;;
        *) warn '1Password vault inventory unavailable'; exit 1 ;;
      esac
      op document create "$file" --vault smm --title raycast-config --tags "$tags" >/dev/null || exit 1 ;;
    *) warn 'Raycast document inventory unavailable; nothing saved'; exit 1 ;;
  esac
  log "Saved Raycast $version export in 1Password vault smm as raycast-config."
)
