{ pkgs, ... }:
let
  # AltTab is pinned at 10.12.0, the version Ethan uses. Upstream no longer
  # hosts that build, so this is the unmodified, notarized app (Developer ID:
  # Louis Pontoise, QXD7GW8FHY) re-hosted on this repo's GitHub release.
  # AltTab is GPL-3.0; source: https://github.com/lwouis/alt-tab-macos/tree/v10.12.0
  alttab = pkgs.stdenvNoCC.mkDerivation {
    pname = "alttab";
    version = "10.12.0";
    src = pkgs.fetchurl {
      url = "https://github.com/ethankeshishian/setup-my-mac/releases/download/alttab-10.12.0/AltTab-10.12.0.zip";
      hash = "sha256-U5/ufC7P88WU9MUOU9NnVpey6xWEWJ+DXU6Dr2OJzsA=";
    };
    nativeBuildInputs = [ pkgs.unzip ];
    sourceRoot = ".";
    # Leave the bundle untouched so its developer signature stays valid.
    dontFixup = true;
    installPhase = ''
      mkdir -p $out/Applications
      cp -R AltTab.app $out/Applications/
    '';
  };
in
{
  environment.systemPackages = [ alttab ];
}
