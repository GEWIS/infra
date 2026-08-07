terraform {
  required_providers {
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
  }
}

variable "kubeconfig_path" {
  description = "Path to the cbc cluster kubeconfig used to probe the cluster and bootstrap flux."
  type        = string
}

variable "flux_cluster_path" {
  description = "Absolute path to the flux cluster directory holding the gotk manifests."
  type        = string
}

data "external" "cluster_identity" {
  program = [
    "bash", "-c",
    "uid=$(kubectl --kubeconfig \"$1\" get namespace kube-system -o jsonpath='{.metadata.uid}' 2>/dev/null || true); printf '{\"uid\":\"%s\"}' \"$uid\"",
    "bash", var.kubeconfig_path,
  ]
}

resource "terraform_data" "flux_bootstrap" {
  triggers_replace = data.external.cluster_identity.result.uid

  provisioner "local-exec" {
    environment = { KUBECONFIG = var.kubeconfig_path }
    command     = <<-EOT
      set -e
      kubectl apply --server-side --force-conflicts -f ${var.flux_cluster_path}/flux-system/gotk-components.yaml
      kubectl wait --for=condition=established --timeout=60s \
        crd/gitrepositories.source.toolkit.fluxcd.io \
        crd/kustomizations.kustomize.toolkit.fluxcd.io
      kubectl apply --server-side \
        -f ${var.flux_cluster_path}/flux-system/gotk-sync.yaml \
        -f ${var.flux_cluster_path}/flux-system.yaml
    EOT
  }
}
