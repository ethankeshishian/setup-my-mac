{
  imports = [
    ./packages.nix
    ./homebrew.nix
    ./alttab.nix
    ./prefs.nix
    ./defaults.nix
    ./services.nix
  ];

  # The host’s Nix installer manages the daemon and its configuration.
  nix.enable = false;
  nixpkgs.hostPlatform = "aarch64-darwin";
  system.primaryUser = "ethankeshishian";
  users.users.ethankeshishian.home = "/Users/ethankeshishian";
  security.pam.services.sudo_local.touchIdAuth = true;

  # Initial nix-darwin compatibility version; keep fixed after migration.
  system.stateVersion = 7;
}
