Run the full suite from the repository root with `nix develop -c bats smm/tests`;
the dev shell provides bats, shellcheck, jq and gitleaks.
Without Nix, `bats smm/tests` works too, and every test in `eval.bats` skips.
`eval.bats` evaluates the Nix configuration once for all its tests (~1–2 min).
Tests use a temporary HOME and PATH stubs for system tools.
Run subsets with `bats --filter 'Dock|Borders' smm/tests`.
