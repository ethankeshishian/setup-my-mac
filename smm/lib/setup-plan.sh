#!/usr/bin/env bash

smm_plan_question() {
  local key=$1 question=$2 recommended=$3 value=$4
  shift 4
  jq -cn --arg key "$key" --arg question "$question" --arg recommended "$recommended" \
    --arg value "$value" --args '{key:$key,question:$question,allowed:$ARGS.positional,
      recommended:(if $recommended == "" then null else $recommended end),
      value:(if $value == "" then null else $value end)}' "$@"
}
smm_setup_plan() (
  destination=$1
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  # Inventory helpers may create transient state (e.g. a Brewfile).
  export SMM_STATE="$tmp/state" SMM_AGENT_SETUP=1 SMM_PLAN=1
  host=$(smm_host) || exit 1
  smm_brew_missing_preview || exit 1
  signed_in=0
  op whoami >/dev/null 2>&1 && signed_in=1
  {
    if ! step_host_done; then
      smm_plan_question host.name 'Host name:' "$host" '' text
      impl=$(jq -r --arg host "$host" '.[$host].nix // empty' "$(smm_repo)/manifest/hosts.json") || exit 1
      [ -n "$impl" ] || smm_plan_question host.nix 'Choose Nix implementation' determinate '' determinate lix
    fi
    smm_plan_question continue 'Continue after preview?' yes '' yes no
    names=$(link_names) || exit 1
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      status=$(smm_migrate_status "$name") || exit 1
      case "$status" in
        linked|missing|same) continue ;;
        repo-newer) value=repo ;;
        *) value='' ;;
      esac
      smm_plan_question "config.$name" "$name: $status" repo "$value" repo local
    done <<< "$names"
    packages=$(smm_brew_undeclared) && duplicates=$(smm_brew_duplicates) || exit 1
    while IFS=' ' read -r kind name; do
      [ -n "$name" ] || continue
      if grep -Fxq "$kind $name" <<< "$duplicates"; then continue; fi
      smm_plan_question "brew.$kind.$name" "$kind $name is installed but not in your setup" skip skip add remove skip
    done <<< "$packages"
    unmanaged=$(smm_brew_unmanaged_casks) || exit 1
    while IFS=$'\t' read -r cask app; do
      [ -n "$cask" ] || continue
      value=''; smm_cask_versions_match "$cask" "$app" && value=adopt
      smm_plan_question "unmanaged.$cask" "$app is installed outside Homebrew" adopt "$value" adopt replace stop
    done <<< "$unmanaged"
    # Without Nix yet, inventory the standard shell entries conservatively.
    # The post-build etc step evaluates the complete real managed entry set.
    if ! command -v nix >/dev/null 2>&1; then
      # shellcheck disable=SC2329 # Invoked by smm_etc_pending.
      smm_etc_entries() { printf '%s\n' '{"zshrc":{"target":"zshrc","enable":true,"knownSha256Hashes":[]},"zshenv":{"target":"zshenv","enable":true,"knownSha256Hashes":[]},"bashrc":{"target":"bashrc","enable":true,"knownSha256Hashes":[]}}'; }
      warn 'Nix is absent: /etc plan covers standard shell files; rerun --plan after the first build for any additional managed entries.'
    fi
    smm_etc_accepted_report >&2 || exit 1
    entries=$(smm_etc_pending) || exit 1
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      name=$(jq -r .name <<< "$entry"); target=$(jq -r .target <<< "$entry")
      smm_plan_question "etc.$name" "Accept the keep/drop review for /etc/$target?" '' '' accept stop
    done <<< "$entries"
    for app in aerospace karabiner alttab; do
      if ! smm_permission_granted "$app"; then
        smm_plan_question "user.$app" "Grant $app permissions in System Settings" 'done' '' 'done'
      fi
    done
    if [ "$signed_in" -eq 0 ]; then
      smm_plan_question signin.op 'Sign in to 1Password now?' now '' now skip
      smm_plan_question user.op 'Unlock/sign in to 1Password and enable CLI integration' 'done' '' 'done'
    fi
    if ! gh auth status >/dev/null 2>&1; then
      smm_plan_question signin.gh 'Sign in to GitHub now?' now '' now skip
      smm_plan_question user.gh 'Complete GitHub web authentication' 'done' '' 'done'
    fi
    if ! step_raycast_done; then
      smm_plan_question user.raycast 'Complete the Raycast password/import dialog' 'done' '' 'done'
    fi
    entries=$(jq -c '.[]' "$(smm_repo)/manifest/secrets.json") || exit 1
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue
      target=$(jq -r .target <<< "$entry"); name=$(jq -r .name <<< "$entry"); ref=$(jq -r .op_ref <<< "$entry")
      [ ! -f "$HOME/$target" ] || continue
      if [ "$signed_in" -eq 0 ]; then
        warn "$name: checked after 1Password sign-in"
        continue
      fi
      path=${ref#op://}; vault=${path%%/*}; path=${path#*/}; item=${path%%/*}
      if ! op item get "$item" --vault "$vault" --format json >/dev/null 2>&1; then
        smm_plan_question "secret.$name.create" "Create missing 1Password item $vault/$item for $name?" no '' yes no
        smm_plan_question "user.secret.$name" "Create/populate $vault/$item in 1Password, then rerun setup" 'done' '' 'done'
      fi
    done <<< "$entries"
    smm_plan_question commit_message 'Commit message:' "Migrate $host to smm" "Migrate $host to smm" text
    smm_plan_question restart 'Restart now?' later later now later
  } > "$tmp/questions" || exit "$?"
  jq -s --arg host "$host" '{host:$host,questions:.}' "$tmp/questions" > "$tmp/answers" || exit 1
  mkdir -p "$(dirname "$destination")" || exit 1
  # Never overwrite decisions from a previous plan without an explicit new path.
  [ ! -e "$destination" ] || { warn "answers file already exists: $destination; use a new --plan path"; exit 1; }
  (umask 077; cp "$tmp/answers" "$destination") || exit 1
  log "Setup answers written to $destination"
)
