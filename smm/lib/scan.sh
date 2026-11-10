#!/usr/bin/env bash

smm_scan_outgoing() (
  range=$1 status=0
  case "$range" in ''|-*) warn 'invalid outgoing revision range'; exit 2 ;; esac
  cd "$(smm_repo)" || exit 1
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  git rev-list --end-of-options "$range" -- > "$tmp/commits" || exit 1
  # Redact findings: the scanner must never print the resolved secret itself.
  gitleaks git "--log-opts=$range" --no-banner --redact || status=1
  jq -r '.[].target' manifest/secrets.json > "$tmp/targets" || exit 1
  if [ -f manifest/links.json ]; then
    resolved=$(links_resolved_json) || exit 1
    jq -r --slurpfile secrets manifest/secrets.json '
      .[] | . as $link | $secrets[0][] | .target as $target |
      select($target == $link.target or
        ($link.type == "dir" and ($target | startswith($link.target + "/")))) |
      $link.source + ($target | ltrimstr($link.target))' <<< "$resolved" >> "$tmp/targets" || exit 1
  fi
  while IFS= read -r commit; do
    git diff-tree --root -m --no-commit-id --name-only -r -z "$commit" -- > "$tmp/paths" || exit 1
    while IFS= read -r -d '' path; do
      hit=0
      case "$path" in *.env.sh) hit=1 ;; esac
      if grep -Fxq -- "$path" "$tmp/targets"; then hit=1; fi
      if [ "$hit" -eq 1 ]; then warn "secret path in outgoing history: $path"; status=1; fi
    done < "$tmp/paths"
  done < "$tmp/commits"
  exit "$status"
)
