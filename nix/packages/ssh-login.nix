{ pkgs }:
pkgs.writeShellApplication {
  name = "ssh-login";
  runtimeInputs = with pkgs; [
    openbao
    openssh
    coreutils
    gnugrep
  ];
  text = ''
    export BAO_ADDR="''${BAO_ADDR:-https://openbao.cbc.gewis.nl:8443}"

    key="''${1:-$HOME/.ssh/id_ed25519}"
    public_key="$key.pub"
    certificate="$key-cert.pub"

    if [ ! -f "$public_key" ]; then
      echo "ssh-login: no public key at $public_key; pass the private key path as the first argument" >&2
      exit 1
    fi

    if ! bao token capabilities ssh/sign/admin 2>/dev/null | grep -qw update; then
      bao login -method=oidc -no-print
    fi

    signed="$(mktemp "$certificate.XXXXXX")"
    trap 'rm -f "$signed"' EXIT
    bao write -field=signed_key ssh/sign/admin \
      public_key=@"$public_key" valid_principals=root,cbc > "$signed"
    chmod 0644 "$signed"
    mv "$signed" "$certificate"

    ssh-keygen -L -f "$certificate"
  '';
}
