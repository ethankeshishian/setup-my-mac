# setup-my-mac

My Apple Silicon Macs, managed with nix-darwin, home-manager, and `smm`.
The repository lives at `~/Repos/setup-my-mac`. Configs link directly into
`config/`, so editing a linked file edits the repo. JSON manifests declare
links, Nix packages, Homebrew packages, and 1Password secret references.
Each host keeps its own `config/zsh/<host>.zshrc`; setup seeds a new host from
its current `~/.zshrc` so local installers can continue appending to it.

## Nix is handled for you

You never run `nix` yourself. `smm setup` installs Nix if it's missing (or
repairs a broken install), and on the first Mac it pins the flake inputs and
commits `flake.lock`. Every later Mac gets that lock from the repo, so all
Macs use the same versions. Lix also works: setup lists modern and legacy profile
packages and asks whether to keep Lix (remembered for reruns) or switch to
Determinate Nix. Switching requires the Lix uninstaller; without it, setup stops
with [Lix uninstall instructions](https://docs.lix.systems/manual/lix/stable/installation/uninstall.html).

## New Mac

On an arm64 Mac running macOS 27:

```bash
curl -fsSL https://raw.githubusercontent.com/ethankeshishian/setup-my-mac/main/bootstrap.sh | bash
```

Bootstrap installs Nix with the Determinate installer if needed, loads its
profile, clones this repo at the fixed path, and runs `smm setup` through Nix.
Run `bash bootstrap.sh --dry-run` to preview its five steps. Rerunning bootstrap
reuses the installation and checkout.

Setup is resumable: fix a failed step and rerun `smm setup`. It backs up local
configs under `~/.smm-backup/<timestamp>/`, compares them with the repo, and lets
you keep either version or pick changes. Sign in to 1Password with CLI integration
and GitHub through `gh auth login` when prompted. Skipping sign-in leaves a
reported degraded state: weather is off or pushing is disabled. Permissions need
your clicks; setup opens the settings panes. Any restart is offered once at the end.

## Existing Mac

A Mac set up with the old script (no Nix yet) runs smm straight from the repo:

```bash
cd ~/Repos/setup-my-mac
git pull
smm/bin/smm setup --preview   # shows every difference, changes nothing
smm/bin/smm setup
```

Setup installs Nix itself. After it finishes, `smm` is on PATH.

## Commands

| Command | When to use it | Behavior |
| --- | --- | --- |
| `smm setup` | Fresh Mac or migration | Compare, back up, build, link configs, guide permissions and sign-ins; safe to rerun. `--preview` shows differences first. |
| `smm apply` | After editing configs | Validate, rebuild changed Nix inputs, activate and check health, then reload valid apps. Failed configs remain untouched and are reported. Versions stay pinned. |
| `smm sync` | Moving between Macs | Validate local edits, prompt for a commit message (or use `-m "message"`), build and validate incoming changes in a temporary worktree, scan outgoing history, apply, then push. Conflicts require a choice. Offline runs stop before a local commit. |
| `smm add <path>` | Keep a local config | Copy into `config/`, declare and link it, then apply. Use `--name <name>` to override the default name. Leaves changes uncommitted. |
| `smm remove <name>` | Stop managing a config | Ask whether to keep a normal local copy or delete it, remove its declaration and repo source, then apply. Keeps a backup. |
| `smm status` | Inspect changes and drift | Show uncommitted edits, ahead/behind commits, undeclared Homebrew packages, broken links and degraded sign-ins or secrets. |
| `smm upgrade` | Deliberate version updates | Update Nix and nvim locks, validate and health-check, then commit the upgrade. Homebrew cask updates require confirmation. Starter template changes are review-only. |
| `smm undo` | Undo an upgrade | Revert the latest unreverted upgrade commit, apply it, and restore pinned nvim plugins. Requires a clean tree. |
| `smm validate [names...]` | Check configs | Run each declared validator, or a named subset. |

`-y` accepts ordinary confirmations. It does **not** silently adopt or uninstall
undeclared Homebrew packages; noninteractive runs warn and leave them alone.
Secrets come from 1Password into ignored or out-of-repo files with mode 600,
are cached between applies, and never belong in a commit. Outgoing history is
scanned before pushing. Setup state lives under `~/.local/state/smm/`.

## Limits

Homebrew casks are not pinned and cannot be rolled back. Self-updating apps can
change independently of `smm`. macOS permissions require manual approval.
Nix-managed state rolls back after activation or health failures; your own edits
to linked configs are preserved. Apps that reload on save may see those edits
before validation.

## Remaining manual steps

Sign in to the App Store and iCloud. Complete any skipped application sign-ins,
and configure shortcuts inside apps such as Raycast and Alt-Tab. After nvim's
history has been migrated and verified, archive `nvchad-starter` on GitHub yourself.

## Development

Run `bats smm/tests` and
`shellcheck -x smm/bin/smm smm/lib/*.sh smm/cmd/*.sh bootstrap.sh setup-my-mac.sh`.
Tests isolate HOME and stub system tools; Nix evaluation tests skip when Nix is
unavailable. The CLI also runs directly as `smm/bin/smm`. Nix builds, stable-package
validation and the attended migration must be verified on a Nix-equipped Mac
before using setup on the live machine.
