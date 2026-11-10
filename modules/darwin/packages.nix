{ pkgs, lib, ... }:
let
  packages = builtins.fromJSON (builtins.readFile ../../manifest/nix-packages.json);
in
{
  environment.systemPackages = (map (name: lib.attrByPath (lib.splitString "." name)
    (throw "Unknown Nix package: ${name}") pkgs) packages)
    ++ [ (pkgs.callPackage ../../smm/package.nix { }) ];
}
