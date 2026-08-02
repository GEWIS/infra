{ lib }:
let
  recipients = import ./recipients.nix;

  anchorOf = lib.replaceStrings [ "-" "." ] [ "_" "_" ];
  adminAnchor = name: "admin_${anchorOf name}";

  adminNames = lib.attrNames recipients.admins;
  adminAnchors = map adminAnchor adminNames;
  hostNames = lib.attrNames recipients.hosts;

  definition = anchor: key: "    - &${anchor} ${key}";

  rule =
    pathRegex: anchors:
    [
      "  - path_regex: ${pathRegex}"
      "    key_groups:"
    ]
    ++ (
      if anchors == adminAnchors then
        [ "      - age: *admins" ]
      else
        [ "      - age:" ] ++ map (anchor: "          - *${anchor}") anchors
    );

  hostRule =
    name:
    let
      host = recipients.hosts.${name};
    in
    rule "secrets/${name}\\.yaml$" (
      lib.optionals (host.adminReadable or true) adminAnchors ++ [ (anchorOf name) ]
    );

  text =
    lib.concatStringsSep "\n" (
      [
        "keys:"
        "  admins: &admins"
      ]
      ++ map (name: definition (adminAnchor name) recipients.admins.${name}) adminNames
      ++ [ "  hosts:" ]
      ++ map (name: definition (anchorOf name) recipients.hosts.${name}.key) hostNames
      ++ [
        ""
        "creation_rules:"
      ]
      ++ rule "secrets/tofu\\.yaml$" adminAnchors
      ++ lib.concatMap hostRule hostNames
    )
    + "\n";
in
{
  inherit text;

  outputsFor =
    pkgs:
    let
      file = pkgs.writeText "sops.yaml" text;
    in
    {
      package = file;

      app = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "sops-config";
            text = ''
              install -m 644 ${file} .sops.yaml
              echo "wrote .sops.yaml — run 'sops updatekeys' on any file whose recipients changed"
            '';
          }
        );
      };

      check = pkgs.runCommand "sops-config-in-sync" { } ''
        if diff -u ${../.sops.yaml} ${file}; then
          touch "$out"
        else
          echo "committed .sops.yaml is stale; run: nix run .#sops-config" >&2
          exit 1
        fi
      '';
    };
}
