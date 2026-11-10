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
      mkHost = host: nix-darwin.lib.darwinSystem {
        inherit system;
        modules = [
          ./hosts/${host}.nix
          ./modules/darwin
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager = {
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
      darwinConfigurations.Ethans-MacBook-Pro = mkHost "Ethans-MacBook-Pro";

      packages.${system}.smm = pkgs.callPackage ./smm/package.nix { };
      apps.${system}.smm = {
        type = "app";
        program = "${pkgs.callPackage ./smm/package.nix { }}/bin/smm";
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ bats shellcheck jq gitleaks git ];
      };
    };
}
