# smm: a Nix-based setup-my-mac

**Status:** design, awaiting approval
**Date:** 2026-11-09

## Intent

`setup-my-mac` today is a bash script that `brew install`s things and **copies** config files from the repo into `$HOME`. Copying means the repo silently drifts from the live configs: Ethan tweaks a live file, it works, and getting that change back into the repo (or removing a config) is a manual, forgettable chore. On 2026-11-09 the repo's `.aerospace.toml` had different gaps, colors and hooks from the live one, the SketchyBar config wasn't in the repo at all, and the nvim copy in the repo is stale and unused.

The replacement is a **nix-darwin + flakes + home-manager** setup driven by one command, `smm`, that covers every moment Ethan touches his setup: setting up a Mac, applying a change, syncing between Macs, adopting or dropping a config, upgrading, and undoing an upgrade.

## Who it's for

Only Ethan, on his own Macs (currently two, Apple Silicon, macOS 27). It is not a generic installer. Usernames, hostnames and app choices can be built in.

## Goals

1. **No drift.** The repo is the single source of truth, and a live config can't silently diverge from it.
2. **Live editing stays fast.** For configs Ethan experiments with, editing the live file *is* editing the repo, with no rebuild, just an app reload.
3. **One command per moment** (see Commands).
4. **It always works.** Applying, syncing or upgrading never leaves an app running on a broken config. Failures roll back automatically.
5. **Setup can't get stuck.** `smm setup` is idempotent and resumable: a failure or Ctrl-C at any point leaves a state where `smm setup` can just be run again.
6. **Upgrades are reversible** (Nix side fully; see Limits).
7. **Both directions of sync**, with Ethan writing the commit message.

## Non-goals

- Supporting other people's machines, Linux, or Intel Macs.
- Granting macOS privacy permissions automatically (impossible without MDM; see Setup).
- Pinning or rolling back apps that update themselves (Arc, Raycast and so on).
- Rolling back Homebrew cask versions.

## Anti-goals (failure even if it "works")

- An `apply`, `sync` or `upgrade` that leaves AeroSpace, SketchyBar, Ghostty, Karabiner, nvim or any other managed app with a broken config. **This is the one Ethan cares about most.**
- `setup` leaving the machine half-configured in a way that blocks re-running it.
- Losing a local config tweak during migration or sync.
- Uninstalling something Ethan installed by hand without asking.
- Pushing a secret, or anything private, to the **public** GitHub repo.
- More than one restart during setup.

## Constraints

- **Public repo** (`github.com/ethankeshishian/setup-my-mac`). No secrets in the repo, ever, not even encrypted. Secrets (such as the SketchyBar weather API key that `scripts/weather.sh` expects in `weather.env.sh`) come from **1Password via the `op` CLI**, which Ethan already uses, and are materialized at apply time into gitignored or out-of-repo files. A scan on 2026-11-09 found no secrets in the current files or history.
- **Repo location is fixed** at `~/Repos/setup-my-mac`, because the linked configs (below) point into it.
- **Existing Macs** were set up with today's script and must be migrated by the same `smm setup` command (see Migration).
- **macOS permissions** (Accessibility, input monitoring, driver approval) can't be scripted.

## Decisions

### Stack (Claude's call, discussed with Ethan)
- **nix-darwin + home-manager, as a flake**, with a pinned `flake.lock` shared by all Macs.
- **Nix installed with the Determinate Systems installer.** nix-darwin config sets `nix.enable = false` so the two don't both manage the Nix daemon.
- One `darwinConfigurations.<hostname>` per Mac. **The Macs are identical** (Ethan): every host imports the same modules, and a host entry holds only its identity (names, below). No per-host overrides until one is actually needed. Current host: `Ethans-MacBook-Pro`, user `ethankeshishian`. The second Mac is "mostly identical" today, but more or less up to date in places (see Migration).

### Where software comes from
- **Ghostty moves from the nightly cask (`ghostty@tip`) to the stable Nix release** (Ethan's decision). The migration must uninstall `ghostty@tip` and validate the config against stable. For example, the live config has `theme = catppuccin-mocha` while the repo copy has `Catppuccin Mocha`, so use whichever name stable accepts.
- **Nix (pinned and validated):** anything whose config Ethan cares about, plus all CLI tools. That means AeroSpace, SketchyBar, JankyBorders, Ghostty, neovim, tmux, the zsh tooling (zsh-autosuggestions, zsh-syntax-highlighting, powerlevel10k, vivid, fzf, zoxide, thefuck), ripgrep, git-town, python, and the language servers nvim needs.
- **Homebrew casks, declared in nix-darwin's `homebrew` module:** GUI apps whose settings live inside the app (Arc, Spotify, Todoist, Obsidian, Clay, Notion Calendar, Raindrop, VS Code, Raycast, alt-tab, Logi Options+, Mos, BetterDisplay, Mac Mouse Fix v2, fonts). Karabiner-Elements stays a cask because of its system driver, but its config is still linked and validated. Homebrew itself is installed declaratively (for example with `nix-homebrew`). Ethan never runs `brew install` by hand.
- **Undeclared Homebrew packages are never removed silently** *(Claude's call, from the anti-goal)*. Before activating, `apply` compares installed packages against the declared ones. If it finds any undeclared ones, it lists them and asks, for each: **add to setup** (writes it into the config) or **remove**. Only then does cleanup run, for exactly the confirmed removals. A non-interactive run (for example `-y`) does neither and just warns. `status` shows them too. Auto-update and upgrade-on-activation are off, so `apply` stays fast and never changes versions.
- The migration has to declare everything this Mac actually has today, not just what the old script installed. The reviewer found formulae (gh, ghc, asdf, pyenv, python@3.9/3.11, postgresql@14, redis, qemu, ffmpeg, luarocks, fd, zsh-vi-mode, zsh-autocomplete, …) and casks (claude-code, codex, vercel, gcloud-cli, gimp, ngrok, pika, kitty, 1password-cli, …). These go through the first-run adopt-or-remove prompt. Where a formula has a good Nix equivalent, prefer Nix.
- Whimsy is Ethan's own browser build, not installed by `smm`. AeroSpace rules for it stay.

### Config files: linked vs. generated
- **Linked to the repo** with home-manager's `mkOutOfStoreSymlink`, so the path in `$HOME` points at the repo file and is live-editable: AeroSpace, SketchyBar, Ghostty, Karabiner, nvim, kitty, tmux, zsh (`.zshrc`, `.p10k.zsh`), Mac Mouse Fix. *(Claude's call: every config currently in `config/` is linked, so no workflow Ethan has today gets slower. Generated configs are fine for new things he doesn't hand-tune.)*
- Karabiner rewrites `karabiner.json` itself, and that can replace a file symlink with a real file. Link the **`~/.config/karabiner` directory**, not the file. The builder should check every linked app for this kind of behavior.
- **macOS settings** (everything in today's `defaults write` block, the `com.apple.symbolichotkeys` edits, `expose-group-apps`) become nix-darwin `system.defaults` or activation scripts, not a bash script.

### Services
- SketchyBar and JankyBorders run as nix-darwin/launchd services. AeroSpace's `after-startup-command` lines that launch them are removed. `exec-on-workspace-change` (the SketchyBar trigger) stays.
- AeroSpace's config stays a **linked file**. Don't use nix-darwin's `services.aerospace.settings`, which generates the config from Nix and would remove live editing. Install the package and start it at login.
- Migrate `.aerospace.toml` from `config-version = 1` to `2`. Recent AeroSpace already warns about it, and a future upgrade would otherwise fail validation.

### nvim
- **Move `~/.config/nvim` (currently its own repo, `github.com/ethankeshishian/nvchad-starter`, 37 commits) into `setup-my-mac` with history** (for example `git subtree add`, or a history merge). Include the uncommitted `lazy-lock.json` changes and `autocmds.lua`. Delete the stale `setup-my-mac/config/nvim` copy. After migration, archive `nvchad-starter` on GitHub. **Ethan does that himself; `smm` never touches the GitHub repo settings.**
- Linked like the other configs.
- **Plugin versions are pinned** by the committed `lazy-lock.json`. `apply`, `sync` and `setup` restore exactly those versions headlessly (`Lazy! restore`). Only `upgrade` updates them.
- NvChad core is the `NvChad/NvChad` plugin on branch `v2.5`, so it updates with `upgrade` and rolls back with `undo`. Moving to a new major branch is a deliberate one-line change. `upgrade` reports when a newer branch exists.
- **Starter template upstream:** `upgrade` checks `github.com/NvChad/starter` for commits since the last one merged into Ethan's fork, and *shows* them for review. It never applies them automatically.
- **Language servers and formatters from Nix**, not Mason (lua-language-server, typescript-language-server, css/html LSPs, stylua, plus whatever `configs/lspconfig.lua` and `conform.lua` reference), so they're pinned. Mason is disabled or unused. Treesitter parsers are installed headlessly or from Nix, so the README's manual `:MasonInstallAll` and `:TSInstall` steps go away.

## Commands

`smm` is on `PATH` after the first build (packaged by the flake). All commands are safe to re-run.

| Command | Purpose | Behavior |
|---|---|---|
| `smm setup` | New Mac, or migrate a Mac set up with the old script | See Setup and Migration. One command, resumable. |
| `smm apply` | "I changed configs" (Ethan's "reload") | Rebuild if Nix-managed inputs changed, then reload running apps (`aerospace reload-config`, `sketchybar --reload`, restart borders, etc.). Goes through the Safety pipeline. Never changes versions. |
| `smm sync` | Moving between Macs | If there are local changes: prompt Ethan for a commit message (`-m "…"` skips the prompt) and commit. Then pull, run the secret and privacy scan, push, and `apply`. On a conflict in the same lines, **stop**, show both versions and ask which to keep. Never merge silently. Nothing to commit means just pull and apply. |
| `smm add <path>` | "I tried a config locally and want to keep it" | Move the file or dir into the repo, replace it with a link, add it to the home-manager config, and apply. Leaves the change uncommitted for the next `sync`. |
| `smm remove <name>` | Drop a config from the setup | Remove it from the config and the repo. Ask whether to leave a normal file in place or delete it. |
| `smm status` | "What's changed?" | Uncommitted config edits, commits not yet pushed or pulled, and drift (Homebrew packages or apps installed but not declared, a linked path that's become a real file). |
| `smm upgrade` | Occasionally | Bump `flake.lock` and nvim plugins, run the starter-template check, then **list the Homebrew cask updates and ask before installing them**, warning that they can't be undone. Casks with linked configs (Karabiner) are validated again after upgrading. Then build, validate against the **new** versions, switch, health-check, then commit (`upgrade: …` listing what changed). Shows a summary of version changes. Committing means other Macs get it on their next `sync`. |
| `smm undo` | Undo the last upgrade | Switch to the previous nix-darwin generation **and** revert the upgrade commit, so the other Macs don't pick it up. Restores the previous `lazy-lock.json` plugin versions. Says plainly that Homebrew cask versions can't be reverted. |

*(Command names are Claude's suggestions, accepted by Ethan. Exact flags and output are left to the builder.)*

## Safety pipeline (every apply, sync, setup and upgrade)

1. **Build first.** Run `darwin-rebuild build` without switching. If it fails, nothing changes.
2. **Validate each app's config with that app's own validator** before switching: AeroSpace (`reload-config --dry-run` or equivalent, which would have caught the 2026-11-09 missing-`if` error), `ghostty +validate-config`, Karabiner's CLI lint, a syntax check of the SketchyBar scripts (`bash -n` / shellcheck), and a headless nvim start that fails on any startup error. Add validators as configs are added.
3. **Switch.**
4. **Health check:** managed apps and services are running and loaded their config without errors.
5. **On any failure in 3–4, automatically roll back** to the previous generation (and previous linked-file state, if `smm` changed it), reload apps, and report what broke.
### Linked files go live immediately (Claude's call)
A linked file is live as soon as it's written. Karabiner reloads on save, and new shells and nvim read the file directly. So "build, validate, switch" can't protect linked files by itself:
- **`sync` validates incoming changes before they reach the working tree.** Fetch, check out the incoming commit in a temporary worktree, and run the validators there. If they fail, **refuse to merge**: this Mac stays on its last good state and `smm` reports which file and validator failed. Being one sync behind is safe; a broken config is not.
- **`sync` also validates before committing and pushing**, so a broken config never reaches the other Mac in the first place.
- **`apply` never modifies or reverts Ethan's own edits to linked files.** If a linked config he edited fails validation, `apply` skips reloading that app, leaves the file untouched and reports the error. Rolling back would throw away his tweak, which is itself an anti-goal. The app keeps running its last loaded config where it supports that (AeroSpace, SketchyBar); for apps that reload on save (Karabiner), the risk of a live edit is accepted, because that's what live editing means.
- Automatic rollback (steps 3–5) therefore applies to **Nix-managed state**: packages, services, defaults, generated files.

6. **Before any push:** scan for secrets and private data (tokens, keys, `op://` resolved values, `weather.env.sh` and similar). Block the push on a hit.
7. `smm` never records window titles, app state or anything outside the declared configs into the repo.

## Setup

**Bootstrap on a fresh Mac:** one documented command from the README (a `curl … | sh` of a small bootstrap script from the repo). It installs Nix (Determinate), clones the repo to `~/Repos/setup-my-mac` using `nix run nixpkgs#git`, and runs the first build, after which `smm setup` takes over. On a Mac that already has the repo, run `smm setup` directly.

**Properties:**
- **Idempotent and resumable.** Every step checks the *real* machine state ("Nix installed?", "config already linked?", "permission granted?") rather than trusting a progress file. Done steps are skipped, so a cancel or failure anywhere is safe to re-run. A progress file is allowed for UX, but never as the source of truth.
- **Nothing is deleted or replaced without a backup first.**
- **A partly installed Nix** (for example after power loss) is detected and repaired with the installer's own repair or uninstall path.
- **New host:** if the hostname has no `darwinConfigurations` entry, `setup` creates one from a template and commits it. *(Claude's call.)*
- **Sign-ins inline, early** *(Claude's call)*. Two waiting steps, run before anything that depends on them:
  - **1Password:** app plus CLI integration, needed for apply-time secrets.
  - **GitHub:** `gh auth login`. Ethan uses `gh` as git's credential helper today, with the SSH protocol. `sync` pushes through that; no personal access token.
  - If either is skipped, setup finishes in a degraded but healthy state: the weather widget is off, push is disabled, and `status` says so. The health check tolerates it.
- **Secrets are cached, not fetched every time:** `op` runs only when a materialized secret file is missing, or on an explicit refresh, so `apply` doesn't trigger a biometric prompt. Vault and item names are the builder's choice. `setup` creates the items if they don't exist; none exist today.
- **Fixed host identity:** each host entry sets its own `HostName`, `LocalHostName` and `ComputerName`, so Bonjour renaming (`…-2`) can't pick the wrong config. New hosts are named by Ethan at setup.
- **Permissions inline.** Right after installing each app that needs one (AeroSpace for Accessibility, Karabiner for driver and input monitoring, any others), open the exact System Settings pane, wait, **detect when it's granted**, and continue by itself.
- **One restart at most, at the end.** Anything that needs a logout or restart (some `defaults`, drivers) is deferred and batched. The finish screen says whether a restart is needed and offers to do it.
- Finishes with a short list of anything left to do by hand (App Store, iCloud, and any sign-in skipped earlier).

## Migration (a Mac set up with the old script)

This is part of the same `smm setup`.

**Order across Macs:** migrate **this Mac (`Ethans-MacBook-Pro`) first**. Its configs were brought up to date on 2026-11-09, and it becomes the baseline in the repo. The second Mac then migrates *against the repo*, and its differences are reconciled in both directions:
- **`smm setup --preview`** runs every check and diff without changing anything, and prints a per-config report: same / repo newer / this Mac newer / both changed, plus packages present on only one side. Ethan looks at the scale before committing to anything.
- **Per config, three choices:** take the repo version, keep this Mac's version, or **merge hunk by hunk** (for files where each side is newer in different places). The result is committed, so the first Mac gets the other Mac's improvements on its next `sync`.
- **nvim on the second Mac:** its `~/.config/nvim` (another clone of `nvchad-starter`, possibly with its own uncommitted changes) is reconciled the same way against the already-migrated copy. Its unpushed commits and uncommitted changes go into the diff and are never discarded. `lazy-lock.json` conflicts default to the newer plugin commit per plugin, which then goes through nvim validation.
- **Packages:** anything only the second Mac has goes through the adopt-or-remove prompt, and adopted packages are added for both Macs.

Steps on each Mac:
1. **Existing real config files** (`~/.aerospace.toml`, `~/.config/sketchybar`, …): show a diff against the repo version and let Ethan keep the repo version, or keep the local one and commit it into the repo. Back up the original either way (for example `~/.smm-backup/<timestamp>/`). Never lose a tweak.
2. **Duplicates:** stop and uninstall Homebrew copies of anything now provided by Nix (sketchybar, borders, AeroSpace cask, neovim, tmux, the zsh tools…) before starting the Nix versions, so two SketchyBars never run at once.
3. **First-run Homebrew cleanup is list-only:** show what `zap` would remove and let Ethan pick (adopt into the config, or remove). Switch to `zap` only after that.
4. **Remove the AeroSpace `after-startup-command` launch lines** (see Services).
5. **Re-grant permissions** for apps whose path changed (AeroSpace from Nix is a different binary to macOS). Same inline flow as Setup.
6. **nvim** is migrated as described above. The fresh-Mac path just uses the repo copy.

## Limits (to state plainly to Ethan, not hide)

- Homebrew casks aren't pinned and can't be rolled back. That's why config-sensitive apps come from Nix.
- Self-updating apps can change underneath `smm`. None of them use the linked dotfiles.
- macOS permissions need Ethan to click; `smm` only removes the hunting around.

## Success looks like

- On either Mac, `smm status` is clean after a `sync`, and both Macs have identical configs and versions.
- A tweak to a linked config is live after a reload and shows up in `git status`. There's no separate copy step.
- No `apply`, `sync` or `upgrade` has ever left an app on a broken config. Failures roll back by themselves.
- A brand-new Mac goes from blank to fully set up with the bootstrap command, the permission clicks and one restart.
- The README's "After install" list shrinks to sign-ins.

## Left to the builder

- The language `smm` is written in (Claude's suggestion: bash via `writeShellApplication`, which runs shellcheck at build time, unless something sturdier is warranted for the resumable setup and rollback logic).
- Exact repo layout (`flake.nix`, `hosts/`, `modules/`, `home/`, `config/`).
- The tool for moving nvim history, and how the starter-upstream check tracks the last merged commit.
- Exact flags, output format and prompts for each command.
- How the health check detects "loaded config without errors" per app.
- Which Homebrew tap and install method (`nix-homebrew` or equivalent).
- Whether today's `setup-my-mac.sh` is deleted or kept as a stub pointing to `smm` (it must not be the supported path).
