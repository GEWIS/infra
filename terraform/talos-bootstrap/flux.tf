module "flux_bootstrap" {
  source            = "./modules/flux-bootstrap"
  kubeconfig_path   = local.kubeconfig_path
  flux_cluster_path = abspath("${path.module}/../../flux/clusters/gewis-prod")
}
