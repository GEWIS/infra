{
  config,
  lib,
  pkgs,
  ...
}:
let
  dataDir = "/var/lib/seaweedfs";

  masterPort = 9333;
  volumePort = 8080;
  filerPort = 8888;
  s3Port = 8333;

  weedShell = pkgs.writeShellApplication {
    name = "seaweedfs-shell";
    runtimeInputs = [ pkgs.seaweedfs ];
    text = ''
      exec weed shell -master=127.0.0.1:${toString masterPort} -filer=127.0.0.1:${toString filerPort}
    '';
  };

  waitForFiler = pkgs.writeShellApplication {
    name = "seaweedfs-wait-for-filer";
    runtimeInputs = [ pkgs.curl ];
    text = ''
      curl --silent --fail --output /dev/null \
        --retry 60 --retry-delay 2 --retry-all-errors \
        http://127.0.0.1:${toString filerPort}/
    '';
  };

  provisionAdmin = pkgs.writeShellApplication {
    name = "seaweedfs-provision-admin";
    runtimeInputs = [ weedShell ];
    text = ''
      seaweedfs-shell <<COMMANDS
      s3.configure -user admin -access_key "$AWS_ACCESS_KEY_ID" -secret_key "$AWS_SECRET_ACCESS_KEY" -actions Admin -apply
      COMMANDS
    '';
  };

  hardening = {
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = true;
    ProtectControlGroups = true;
    ProtectHome = true;
    ProtectKernelModules = true;
    ProtectKernelTunables = true;
    ProtectSystem = "strict";
    RestrictAddressFamilies = [
      "AF_INET"
      "AF_INET6"
      "AF_UNIX"
    ];
    RestrictNamespaces = true;
    RestrictRealtime = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [ "@system-service" ];
  };
in
{
  systemd = {
    services = {
      seaweedfs = {
        description = "SeaweedFS object storage";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = hardening // {
          ExecStart = lib.escapeShellArgs [
            (lib.getExe pkgs.seaweedfs)
            "server"
            "-dir=${dataDir}"
            "-ip=127.0.0.1"
            "-ip.bind=127.0.0.1"
            "-master.port=${toString masterPort}"
            "-volume.port=${toString volumePort}"
            "-volume.max=0"
            "-filer"
            "-filer.port=${toString filerPort}"
            "-s3"
            "-s3.ip.bind=0.0.0.0"
            "-s3.port=${toString s3Port}"
            "-s3.port.iceberg=0"
            "-s3.iam.readOnly=false"
          ];

          User = "seaweedfs";
          Group = "seaweedfs";
          StateDirectory = "seaweedfs";
          StateDirectoryMode = "0750";
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
      seaweedfs-admin = {
        description = "Provision the SeaweedFS admin identity";
        after = [ "seaweedfs.service" ];
        requires = [ "seaweedfs.service" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = hardening // {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStartPre = lib.getExe waitForFiler;
          ExecStart = lib.getExe provisionAdmin;
          EnvironmentFile = config.sops.templates."seaweedfs-admin.env".path;
          User = "seaweedfs";
          Group = "seaweedfs";
          Restart = "on-failure";
          RestartSec = 5;
        };
      };
    };
  };

  users.users.seaweedfs = {
    isSystemUser = true;
    group = "seaweedfs";
  };
  users.groups.seaweedfs = { };

  sops = {
    secrets = {
      seaweedfs-admin-access-key = { };
      seaweedfs-admin-secret-key = { };
    };

    templates."seaweedfs-admin.env" = {
      owner = "seaweedfs";
      mode = "0400";
      restartUnits = [ "seaweedfs-admin.service" ];
      content = ''
        AWS_ACCESS_KEY_ID=${config.sops.placeholder.seaweedfs-admin-access-key}
        AWS_SECRET_ACCESS_KEY=${config.sops.placeholder.seaweedfs-admin-secret-key}
      '';
    };
  };

  networking.firewall.allowedTCPPorts = [ s3Port ];
}
