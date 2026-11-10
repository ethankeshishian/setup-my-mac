let
  manifest = builtins.fromJSON (builtins.readFile ../../manifest/homebrew.json);
in
{
  nix-homebrew = {
    enable = true;
    user = "ethankeshishian";
    autoMigrate = true;
  };

  homebrew = {
    enable = true;
    inherit (manifest) taps brews casks;
    onActivation = {
      cleanup = "none";
      autoUpdate = false;
      upgrade = false;
    };
  };
}
