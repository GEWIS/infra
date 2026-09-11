{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./lib.nix { inherit config lib pkgs; }) cfg sessionUnit;
in
{
  config = lib.mkIf cfg.enable {
    systemd.user.services = lib.mapAttrs' (
      name: app:
      lib.nameValuePair "service-pc-app-${name}" (sessionUnit {
        description = "${name} for the service-PC session";
        exec = if app.exec != null then app.exec else lib.getExe app.package;
        inherit (app) wmClass workspace monitor;
      })
    ) cfg.apps;

    environment.systemPackages = lib.mapAttrsToList (_: app: app.package) cfg.apps;
  };
}
