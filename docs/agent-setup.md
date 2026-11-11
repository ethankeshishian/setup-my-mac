# Run setup with an agent

Paste this to the agent on the Mac being migrated:

> Work from `~/Repos/setup-my-mac`. Run `smm/bin/smm setup --plan` to write
> `~/Desktop/smm-answers.json`. This inventories configs and packages without
> installing, removing, or activating anything. If a plan already exists, use a
> different filename to preserve its decisions.
>
> Fill each question's `value` using Ethan's stated decisions. Keep the question
> keys and allowed values. Never remove direnv or work tools. Use `repo` for configs
> Ethan approved; use `skip` for Homebrew packages when unsure. Leave unresolved
> config conflicts, replacements, and `/etc` reviews as `null` until Ethan decides.
> Never select `remove` or `replace` based only on a recommendation. Only matching
> unmanaged app versions, and casks with `auto_updates: true` even when versions
> differ, are safely pre-filled as `adopt`; `replace` remains an explicit choice.
> `restart` defaults to `later`. `commit_message` defaults to `Migrate <host> to smm`.
>
> Run `smm/bin/smm setup --answers ~/Desktop/smm-answers.json` (substitute your
> chosen plan path) **in the background**, for example with Claude Code's
> `run_in_background`. Follow its streamed output or poll the background task and
> `~/.local/state/smm/setup.log` until the process exits. Never let a tool timeout
> kill setup: timeouts send TERM mid-step, potentially during installation or
> activation. Rerun only after the previous process has exited.
> Exit code 3 pauses setup without rolling anything back; rerunning resumes it.
> On exit code 3, read the `SMM-NEEDS:` lines in the output or
> `~/.local/state/smm/needs.log`. Relay requested user actions to Ethan verbatim.
> `SMM-WAITING:` means setup is polling for up to ten minutes while Ethan acts.
> For a missing answer, obtain Ethan's decision and fill its `value`. For an
> undetectable action such as AltTab permissions or Raycast import, set
> `user.<key>` to `done` in the matching question only after Ethan confirms it.
> After he confirms and the previous process exits, rerun the same setup command
> in the background; setup checks real state again.
> New questions can appear after installing Nix or selecting a new host. Add them
> to `questions` with the exact key and allowed values from `SMM-NEEDS`, or write a
> fresh plan to a new path and carry over Ethan's confirmed decisions.
>
> Never edit `/etc`. Setup shows exactly which lines it will keep and drop, writes
> accepted changes to `hosts/etc/<host>.nix`, and rebuilds before activation.
> Accepted entries produce no `etc.*` question; `--plan` lists them as already
> accepted. Run the read-only `smm/bin/smm etc review` to see the classifier
> keep/drop output. Each file is labeled pending, already accepted, or known
> stock (replaced entirely by nix-darwin, so nothing in it is kept). Relay
> that complete review to Ethan before setting `etc.<name>` to `accept`. Uncertain
> macOS stock lines are conservatively kept. Never run sudo yourself, never answer
> a password dialog, and never handle Ethan's password. Setup requests it through
> its own macOS password dialog when necessary.
>
> Report completed steps, remaining `SMM-NEEDS` actions, generated host files,
> tests/validation performed, commit details, and restart status at the end.

The file format is an object with `host` and `questions`. Each question has `key`,
`question`, `allowed`, `recommended`, and `value`. `null` means undecided. Setup
also accepts a flat object mapping exact keys to strings, such as
`{"config.zsh":"repo","brew.brew.direnv":"skip","restart":"later"}`.
Invalid answers fail; `-y` does not authorize destructive package decisions or
acknowledge user actions. Do not put secrets or passwords in the answers file.

Nix-free planning can inventory the standard `/etc/zshrc`, `/etc/zshenv`, and
`/etc/bashrc` files. Once Nix is available, planning and the post-build takeover
step evaluate nix-darwin's complete enabled `/etc` entries. The latter may require
additional decisions. Production setup still enforces the repository's attended
migration preflight (Apple Silicon, fixed checkout location, branch `main`).

`--plan` and `--preview` list declared Homebrew packages that are missing. Setup
and `apply` install these as the user before building and switching, without
upgrading installed packages. Installer/pkg casks may open a macOS password
dialog. When 1Password is signed out, missing secret items are checked after
1Password sign-in; the plan does not ask to create them yet.

When updating a checkout with local migration changes, preserve them with
`git stash push -u && git pull`. Before restoring the stash, check
`git diff c5f1f1c stash@{0} --stat` (empty = nothing lost). This compares the
saved pre-pull state to the migration baseline.
