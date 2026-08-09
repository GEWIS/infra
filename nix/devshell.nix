{ pkgs }:
pkgs.mkShellNoCC {
  name = "cbc-infra";
  packages = with pkgs; [
    age
    jq
    kubectl
    kubeseal
    fluxcd
    k9s
    nixfmt
    cilium-cli
    openbao
    nixos-anywhere
    opentofu
    sops
    ssh-to-age
    talosctl
    (import ./packages/mint-creds.nix { inherit pkgs; })
    (python3.withPackages (ps: [ ps.mkdocs-material ]))
  ];
}
