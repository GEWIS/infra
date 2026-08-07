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
    nixos-anywhere
    opentofu
    sops
    ssh-to-age
    talosctl
    (import ./packages/mint-creds.nix { inherit pkgs; })
  ];
}
