{ pkgs }:
pkgs.mkShellNoCC {
  name = "cbc-infra";
  packages = with pkgs; [
    age
    jq
    kubectl
    k9s
    nixfmt
    nixos-anywhere
    opentofu
    sops
    ssh-to-age
    talosctl
    (import ./packages/mint-creds.nix { inherit pkgs; })
  ];
}
