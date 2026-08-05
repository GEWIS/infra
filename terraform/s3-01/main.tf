locals {
  ssh_authorized_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHnm7ME9L/KuEGbSbzPJ4uVgsNl579UCCtXAIlWNYq7x luuk-blankenstijn@luuk-laptop"

  placement = {
    pool_name_label     = "GEWISVHOST-Intel"
    template_name_label = "DevVM Ubuntu 24.04 LTS basis"
    network_name_label  = "External"
    sr_name_label       = "vhost1-ssd2"
    expected_ip_cidr    = "10.82.50.0/24"
  }

  hosts = {
    s3-01 = {
      mac_address   = "00:16:3e:5e:a1:01"
      cpus          = 4
      memory_gib    = 8
      root_disk_gib = 40
      data_disk_gib = 100
    }
  }
}

module "vm" {
  for_each = local.hosts
  source   = "../modules/xcpng-vm"

  vm_name             = each.key
  pool_name_label     = local.placement.pool_name_label
  template_name_label = local.placement.template_name_label
  network_name_label  = local.placement.network_name_label
  sr_name_label       = local.placement.sr_name_label
  expected_ip_cidr    = local.placement.expected_ip_cidr

  cpus          = each.value.cpus
  memory_gib    = each.value.memory_gib
  root_disk_gib = each.value.root_disk_gib
  data_disk_gib = each.value.data_disk_gib
  mac_address   = each.value.mac_address

  cloud_config = <<-EOT
#cloud-config
hostname: ${each.key}
disable_root: false
package_update: true
packages:
  - openssh-server
  - xe-guest-utilities
write_files:
  - path: /etc/default/grub.d/99-net-ifnames.cfg
    content: |
      GRUB_CMDLINE_LINUX_DEFAULT="$GRUB_CMDLINE_LINUX_DEFAULT net.ifnames=0"
runcmd:
  - install -d -m 700 /root/.ssh
  - printf '%s\n' '${local.ssh_authorized_key}' > /root/.ssh/authorized_keys
  - chmod 600 /root/.ssh/authorized_keys
  - systemctl enable --now ssh
  - update-grub
  - systemctl enable xe-daemon
power_state:
  mode: reboot
  condition: true
EOT
}

module "nixos" {
  for_each = local.hosts
  source   = "../modules/nixos-host"

  target_host = module.vm[each.key].vm_ipv4
  instance_id = module.vm[each.key].vm_id

  nixos_system_attr      = "${path.module}/../..#nixosConfigurations.${each.key}.config.system.build.toplevel"
  nixos_partitioner_attr = "${path.module}/../..#nixosConfigurations.${each.key}.config.system.build.diskoScript"

  extra_files_script = "${path.module}/extra-files.sh"
  extra_environment  = { HOST_AGE_KEY = var.host_age_key }

  build_on_remote = false
}
