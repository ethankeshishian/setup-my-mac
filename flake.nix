{
  description = "Ethan's declarative Mac setup";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # nix-homebrew has no nixpkgs input to follow.
    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs = { nixpkgs, nix-darwin, home-manager, nix-homebrew, ... }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs { inherit system; };
      mkHost = host:
        let
          hostIdentity = import ./hosts/${host}.nix;
          hostName = hostIdentity.networking.localHostName;
        in nix-darwin.lib.darwinSystem {
          inherit system;
          specialArgs = { inherit hostName; };
          modules = [
            hostIdentity
            ./modules/darwin
            nix-homebrew.darwinModules.nix-homebrew
            home-manager.darwinModules.home-manager
            {
              home-manager = {
                extraSpecialArgs = { inherit hostName; };
                useGlobalPkgs = true;
                useUserPackages = true;
                backupFileExtension = null;
                users.ethankeshishian = import ./modules/home;
              };
            }
          ];
        };
    in
    {
      darwinConfigurations = builtins.listToAttrs (map
        (file: let host = nixpkgs.lib.removeSuffix ".nix" file;
          in { name = host; value = mkHost host; })
        (builtins.filter (file: file != "template.nix"
          && nixpkgs.lib.hasSuffix ".nix" file
          && (builtins.readDir ./hosts).${file} == "regular")
          (builtins.attrNames (builtins.readDir ./hosts))));

      # ${system} is a dynamic name, so each attrset must be defined once.
      packages.${system} = {
        darwin-rebuild = nix-darwin.packages.${system}.darwin-rebuild;
        smm = pkgs.callPackage ./smm/package.nix { };
      };
      apps.${system} = {
        darwin-rebuild = {
          type = "app";
          program = "${nix-darwin.packages.${system}.darwin-rebuild}/bin/darwin-rebuild";
        };
        smm = {
          type = "app";
          program = "${pkgs.callPackage ./smm/package.nix { }}/bin/smm";
        };
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ bats shellcheck jq gitleaks git ];
      };
    };
}
