module "nixos_anywhere" {
  source = "github.com/numtide/nixos-anywhere//terraform/all-in-one?ref=1.13.0"

  nixos_system_attr      = var.nixos_system_attr
  nixos_partitioner_attr = var.nixos_partitioner_attr

  target_host = var.target_host
  target_user = var.target_user

  instance_id = var.instance_id

  extra_files_script = var.extra_files_script
  extra_environment  = var.extra_environment

  build_on_remote = var.build_on_remote
}
