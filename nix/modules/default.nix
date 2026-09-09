{ ... }:
{
  imports = [
    ./admin.nix
    ./comin.nix
    ./common.nix
    ./motd.nix
    ./netbird.nix
    ./persistence.nix
    ./service-pc
    ./shell.nix
    ./tmpfs-root.nix
    ./zabbix-agent.nix
  ];
}
