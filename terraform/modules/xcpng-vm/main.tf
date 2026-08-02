locals {
  gib = 1024 * 1024 * 1024

  bootstrap_cloud_config = <<-EOT
#cloud-config
hostname: ${var.vm_name}
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
  - printf '%s\n' '${var.ssh_authorized_key}' > /root/.ssh/authorized_keys
  - chmod 600 /root/.ssh/authorized_keys
  - systemctl enable --now ssh
  - update-grub
  - systemctl enable xe-daemon
power_state:
  mode: reboot
  condition: true
EOT
}

data "xenorchestra_pool" "pool" {
  name_label = var.pool_name_label
}

data "xenorchestra_template" "base" {
  name_label = var.template_name_label
}

data "xenorchestra_network" "net" {
  name_label = var.network_name_label
  pool_id    = data.xenorchestra_pool.pool.id
}

data "xenorchestra_sr" "disks" {
  name_label = var.sr_name_label
  pool_id    = data.xenorchestra_pool.pool.id
}

resource "xenorchestra_vm" "this" {
  name_label = var.vm_name
  template   = data.xenorchestra_template.base.id

  cpus       = var.cpus
  memory_max = var.memory_gib * local.gib

  hvm_boot_firmware = var.hvm_boot_firmware
  clone_type        = var.clone_type
  auto_poweron      = var.auto_poweron
  cloud_config      = local.bootstrap_cloud_config

  network {
    network_id       = data.xenorchestra_network.net.id
    mac_address      = var.mac_address
    expected_ip_cidr = var.expected_ip_cidr
  }

  disk {
    sr_id      = data.xenorchestra_sr.disks.id
    name_label = "${var.vm_name}-root"
    size       = var.root_disk_gib * local.gib
  }

  disk {
    sr_id      = data.xenorchestra_sr.disks.id
    name_label = "${var.vm_name}-data"
    size       = var.data_disk_gib * local.gib
  }

  timeouts {
    create = "20m"
  }

  lifecycle {
    ignore_changes = [affinity_host]
  }
}
