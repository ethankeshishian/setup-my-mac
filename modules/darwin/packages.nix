{ pkgs, ... }:
let
  packages = builtins.fromJSON (builtins.readFile ../../manifest/nix-packages.json);
in
{
  environment.systemPackages = (map (name: pkgs.${name}) packages)
    ++ [ (pkgs.callPackage ../../smm/package.nix { }) ];
}
