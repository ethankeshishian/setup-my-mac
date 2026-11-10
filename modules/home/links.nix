{ config, lib, hostName, ... }:
let
  links = builtins.fromJSON (builtins.readFile ../../manifest/links.json);
  repo = "/Users/ethankeshishian/Repos/setup-my-mac";
in
{
  home.file = lib.listToAttrs (map (link: {
    name = link.target;
    value = {
      source = config.lib.file.mkOutOfStoreSymlink "${repo}/${lib.replaceStrings [ "{host}" ] [ hostName ] link.source}";
      # Link a whole directory so apps that atomically rewrite files stay linked.
      recursive = false;
    };
  }) links);
}
