{ pkgs }:
pkgs.writeShellApplication {
  name = "mint-creds";
  runtimeInputs = with pkgs; [
    talosctl
    sops
    openssl
    coreutils
    git
  ];
  text = ''
    root="''${CBC_REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    secrets="''${CBC_TALOS_SECRETS:-$root/secrets/talos.yaml}"
    talosconfig="''${1:-$root/.talos/config}"
    kubeconfig="''${2:-$root/.kube/config}"

    cluster="cbc"
    endpoint="https://kube.gewis.nl:6443"
    nodes=(10.82.50.101 10.82.50.102 10.82.50.103)

    work="$(mktemp -d)"
    trap 'rm -rf "$work"' EXIT
    cd "$work" || exit 1

    ca() { sops -d --extract "[\"certs\"][\"$1\"][\"$2\"]" "$secrets" | base64 -d; }

    ca os crt >os.crt
    ca os key >os.key
    talosctl gen key --name talos >/dev/null
    talosctl gen csr --key talos.key --roles os:admin --ip 127.0.0.1 >/dev/null
    talosctl gen crt --ca os --csr talos.csr --hours 876000 --name talos >/dev/null

    mkdir -p "$(dirname "$talosconfig")"
    {
      printf 'context: %s\ncontexts:\n    %s:\n        endpoints:\n' "$cluster" "$cluster"
      printf '            - %s\n' "''${nodes[@]}"
      printf '        nodes:\n            - %s\n' "''${nodes[0]}"
      printf '        ca: %s\n        crt: %s\n        key: %s\n' \
        "$(base64 -w0 os.crt)" "$(base64 -w0 talos.crt)" "$(base64 -w0 talos.key)"
    } >"$talosconfig"
    chmod 600 "$talosconfig"

    ca k8s crt >k8s.crt
    ca k8s key >k8s.key
    openssl genpkey -algorithm ec -pkeyopt ec_paramgen_curve:P-256 -out kube.key
    openssl req -new -key kube.key -subj "/CN=admin/O=system:masters" -out kube.csr
    openssl x509 -req -in kube.csr -CA k8s.crt -CAkey k8s.key -CAcreateserial \
      -not_after 99991231235959Z \
      -extfile <(printf 'keyUsage=critical,digitalSignature\nextendedKeyUsage=clientAuth\n') \
      -out kube.crt

    mkdir -p "$(dirname "$kubeconfig")"
    {
      printf 'apiVersion: v1\nkind: Config\ncurrent-context: %s\n' "$cluster"
      printf 'clusters:\n    - name: %s\n      cluster:\n        server: %s\n' "$cluster" "$endpoint"
      printf '        certificate-authority-data: %s\n' "$(base64 -w0 k8s.crt)"
      printf 'users:\n    - name: admin\n      user:\n'
      printf '        client-certificate-data: %s\n        client-key-data: %s\n' \
        "$(base64 -w0 kube.crt)" "$(base64 -w0 kube.key)"
      printf 'contexts:\n    - name: %s\n      context:\n        cluster: %s\n        user: admin\n' "$cluster" "$cluster"
    } >"$kubeconfig"
    chmod 600 "$kubeconfig"
  '';
}
