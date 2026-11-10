Run the full suite from the repository root: `bats smm/tests`.
Tests use a temporary HOME and PATH stubs for system tools.
`eval.bats` needs Nix and performs one evaluation (~1–2 min).
Without Nix, all tests in `eval.bats` skip with `nix not installed`.
Run subsets with `bats --filter 'Dock|Borders' smm/tests`.
