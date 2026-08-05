locals {
  cluster_name     = "cbc"
  cluster_endpoint = "https://kube.gewis.nl:6443"
  talos_version    = "v1.13.8"
  schematic_id     = "544579955b64479597e31a593d522bfa8c9ce21939264e852e54c55e11b4d788"
  install_image    = "factory.talos.dev/installer/${local.schematic_id}:${local.talos_version}"

  pool_name_label     = "GEWISVHOST-Intel"
  network_name_label  = "External"
  template_name_label = "talos-1.13.8-nocloud"

  pod_subnets     = ["10.244.0.0/16", "fd00:cbc:0::/56"]
  service_subnets = ["10.96.0.0/12", "fd00:cbc:1::/108"]

  nodes = {
    talos-01 = { ip = "10.82.50.101", mac = "00:16:3e:5e:b8:01", host = "gewisvhost1.win.tue.nl", sr = "vhost1-ssd2" }
    talos-02 = { ip = "10.82.50.102", mac = "00:16:3e:5e:b8:02", host = "gewisvhost1.win.tue.nl", sr = "vhost1-ssd2" }
    talos-03 = { ip = "10.82.50.103", mac = "00:16:3e:5e:b8:03", host = "gewisvhost3.win.tue.nl", sr = "vhost3-ssd" }
  }

  bootstrap_node = "talos-01"

  bundle = yamldecode(var.talos_secrets)
  machine_secrets = {
    cluster    = local.bundle.cluster
    trustdinfo = local.bundle.trustdinfo
    secrets = {
      bootstrap_token             = local.bundle.secrets.bootstraptoken
      secretbox_encryption_secret = local.bundle.secrets.secretboxencryptionsecret
      aescbc_encryption_secret    = try(local.bundle.secrets.aescbcencryptionsecret, null)
    }
    certs = {
      etcd               = { cert = local.bundle.certs.etcd.crt, key = local.bundle.certs.etcd.key }
      k8s                = { cert = local.bundle.certs.k8s.crt, key = local.bundle.certs.k8s.key }
      k8s_aggregator     = { cert = local.bundle.certs.k8saggregator.crt, key = local.bundle.certs.k8saggregator.key }
      k8s_serviceaccount = { key = local.bundle.certs.k8sserviceaccount.key }
      os                 = { cert = local.bundle.certs.os.crt, key = local.bundle.certs.os.key }
    }
  }

  cluster_patch = yamlencode({
    cluster = {
      allowSchedulingOnControlPlanes = true
      network = {
        cni            = { name = "none" }
        podSubnets     = local.pod_subnets
        serviceSubnets = local.service_subnets
      }
      proxy = { disabled = true }
    }
    machine = {
      install = { disk = "/dev/xvda", image = local.install_image }
      kubelet = { nodeIP = { validSubnets = ["10.82.50.0/24"] } }
    }
  })

  longhorn_volume = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "UserVolumeConfig"
    name       = "longhorn"
    provisioning = {
      diskSelector = { match = "!system_disk" }
      minSize      = "1GiB"
      grow         = true
    }
    filesystem = { type = "xfs" }
  })
}

data "xenorchestra_host" "node_host" {
  for_each   = toset([for n in values(local.nodes) : n.host])
  name_label = each.key
}

module "vm" {
  for_each = local.nodes
  source   = "../modules/xcpng-vm"

  vm_name             = each.key
  pool_name_label     = local.pool_name_label
  template_name_label = local.template_name_label
  network_name_label  = local.network_name_label
  sr_name_label       = each.value.sr
  affinity_host       = data.xenorchestra_host.node_host[each.value.host].id

  mac_address   = each.value.mac
  cpus          = 4
  memory_gib    = 8
  root_disk_gib = 20
  data_disk_gib = 10

  cloud_config     = null
  expected_ip_cidr = ""
}

resource "terraform_data" "cert_nbf" {
  input = plantimestamp()

  lifecycle {
    ignore_changes = [input]
  }
}

ephemeral "talos_client_configuration" "this" {
  cluster_name    = local.cluster_name
  machine_secrets = local.machine_secrets
  endpoints       = [for n in values(local.nodes) : n.ip]
  not_before      = terraform_data.cert_nbf.output
}

ephemeral "talos_machine_configuration" "controlplane" {
  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = "controlplane"
  machine_secrets  = local.machine_secrets
  talos_version    = local.talos_version
  docs             = false
  examples         = false
  config_patches = [
    local.cluster_patch,
    local.longhorn_volume,
  ]
}

resource "talos_machine_configuration_apply" "this" {
  for_each = local.nodes

  node                           = each.value.ip
  endpoint                       = each.value.ip
  client_configuration_wo        = ephemeral.talos_client_configuration.this.client_configuration
  machine_configuration_input_wo = ephemeral.talos_machine_configuration.controlplane.machine_configuration

  depends_on = [module.vm]
}

resource "talos_machine_bootstrap" "this" {
  node                    = local.nodes[local.bootstrap_node].ip
  endpoint                = local.nodes[local.bootstrap_node].ip
  client_configuration_wo = ephemeral.talos_client_configuration.this.client_configuration

  depends_on = [talos_machine_configuration_apply.this]
}
