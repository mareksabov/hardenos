{
  description = "Browser-centric NixOS — minimal, hardened, browser-first OS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      mkHost = system: hostModule:
        lib.nixosSystem {
          inherit system;
          modules = [ ./modules/default.nix hostModule ];
        };
    in {
      nixosConfigurations = {
        vm = mkHost "aarch64-linux" ./hosts/vm/default.nix;
        laptop = mkHost "x86_64-linux" ./hosts/laptop/default.nix;
      };

      devShells = lib.genAttrs
        [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ]
        (system:
          let pkgs = nixpkgs.legacyPackages.${system}; in {
            default = pkgs.mkShell {
              packages = [ pkgs.nixpkgs-fmt pkgs.git ];
            };
          });
    };
}
