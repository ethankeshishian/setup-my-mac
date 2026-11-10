{ lib, ... }:
let
  directory = ../../manifest/prefs;
  files = builtins.filter
    (name: lib.hasSuffix ".json" name && (builtins.readDir directory).${name} == "regular")
    (builtins.attrNames (builtins.readDir directory));
in
{
  system.defaults.CustomUserPreferences = builtins.listToAttrs (map
    (name: {
      name = lib.removeSuffix ".json" name;
      value = (builtins.fromJSON (builtins.readFile (directory + "/${name}"))).keys;
    })
    files);
}
