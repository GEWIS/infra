{
  description = "GEWIS CBC infrastructure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    comin = {
      url = "github:nlewo/comin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    geprint.url = "github:GEWIS/GEPRINT";

    impermanence.url = "github:nix-community/impermanence";

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      comin,
      disko,
      geprint,
      impermanence,
      sops-nix,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      pkgsFor = system: nixpkgs.legacyPackages.${system};

      host =
        name: extraModules:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs; };
          modules = [
            { nixpkgs.hostPlatform = "x86_64-linux"; }
            disko.nixosModules.disko
            sops-nix.nixosModules.sops
            ./nix/modules
            ./nix/hosts/${name}
          ]
          ++ extraModules;
        };
    in
    {
      nixosConfigurations = {
        s3-01 = host "s3-01" [ ];

        pcgewisinfo = host "pcgewisinfo" [
          comin.nixosModules.comin
          geprint.nixosModules.default
          impermanence.nixosModules.impermanence
        ];
      };

      devShells = forAllSystems (
        system:
        let
          pkgs = pkgsFor system;
        in
        {
          default = pkgs.mkShellNoCC {
            name = "cbc-infra";
            packages = with pkgs; [
              age
              jq
              nixfmt
              nixos-anywhere
              opentofu
              sops
              ssh-to-age
            ];
          };
        }
      );

      formatter = forAllSystems (system: (pkgsFor system).nixfmt);
    };
}
