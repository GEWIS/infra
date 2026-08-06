locals {
  flux_cluster_path = "${path.module}/../../flux/clusters/gewis-prod"
}

data "kubectl_file_documents" "flux_components" {
  content = file("${local.flux_cluster_path}/flux-system/gotk-components.yaml")
}

resource "kubectl_manifest" "flux_components" {
  for_each          = data.kubectl_file_documents.flux_components.manifests
  yaml_body         = each.value
  server_side_apply = true
  force_conflicts   = true
}

data "kubectl_file_documents" "flux_sync" {
  content = join("\n---\n", [
    file("${local.flux_cluster_path}/flux-system/gotk-sync.yaml"),
    file("${local.flux_cluster_path}/flux-system.yaml"),
  ])
}

resource "kubectl_manifest" "flux_sync" {
  for_each          = data.kubectl_file_documents.flux_sync.manifests
  yaml_body         = each.value
  server_side_apply = true

  depends_on = [kubectl_manifest.flux_components]
}
