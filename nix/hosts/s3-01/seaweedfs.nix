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

  # Read by node exporter's textfile collector; the backup unit writes its result here.
  textfileDir = "/var/lib/prometheus-node-exporter-text";

  backup = pkgs.writeShellApplication {
    name = "seaweedfs-backup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnused
      pkgs.rclone
    ];
    text = builtins.readFile ./seaweedfs-backup.sh;
  };

  # Runs as root after every backup run, successful or not (ExecStopPost).
  backupMetrics = pkgs.writeShellApplication {
    name = "seaweedfs-backup-metrics";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      now="$(date +%s)"
      success=0
      if [ "''${SERVICE_RESULT:-}" = success ]; then
        success=1
      fi

      # Atomic: the collector only reads *.prom, never the .tmp file.
      write() {
        cat >"${textfileDir}/$1.tmp"
        mv "${textfileDir}/$1.tmp" "${textfileDir}/$1"
      }

      write seaweedfs_backup_last_run.prom <<EOF
      # HELP seaweedfs_backup_last_run_timestamp_seconds When the last off-site backup run ended.
      # TYPE seaweedfs_backup_last_run_timestamp_seconds gauge
      seaweedfs_backup_last_run_timestamp_seconds $now
      # HELP seaweedfs_backup_last_run_success Whether the last off-site backup run succeeded.
      # TYPE seaweedfs_backup_last_run_success gauge
      seaweedfs_backup_last_run_success $success
      EOF

      if [ "$success" = 1 ]; then
        write seaweedfs_backup_last_success.prom <<EOF
      # HELP seaweedfs_backup_last_success_timestamp_seconds When the last successful off-site backup run ended.
      # TYPE seaweedfs_backup_last_success_timestamp_seconds gauge
      seaweedfs_backup_last_success_timestamp_seconds $now
      EOF
      fi
    '';
  };

  hardening = {
    NoNewPrivileges = true;
    PrivateDevices = true;
    PrivateTmp = "disconnected";
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
            "-master.volumeSizeLimitMB=1024"
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

      # Off-site copy to Scaleway, self-contained on this host so it keeps running
      # while the cluster is down. See docs/seaweedfs-backup/.
      seaweedfs-backup = {
        description = "Copy SeaweedFS buckets off-site to Scaleway";
        after = [
          "network-online.target"
          "seaweedfs-admin.service"
        ];
        wants = [ "network-online.target" ];

        environment = {
          HOME = "/tmp";
          DESTINATION = "gewis-seaweedfs-backup";
          RCLONE_CONFIG_SEAWEEDFS_TYPE = "s3";
          RCLONE_CONFIG_SEAWEEDFS_PROVIDER = "SeaweedFS";
          RCLONE_CONFIG_SEAWEEDFS_ENDPOINT = "http://127.0.0.1:${toString s3Port}";
          RCLONE_CONFIG_SEAWEEDFS_REGION = "us-east-1";
          RCLONE_CONFIG_SCALEWAY_TYPE = "s3";
          RCLONE_CONFIG_SCALEWAY_PROVIDER = "Scaleway";
          RCLONE_CONFIG_SCALEWAY_REGION = "nl-ams";
          RCLONE_CONFIG_SCALEWAY_ENDPOINT = "s3.nl-ams.scw.cloud";
          RCLONE_CONFIG_SCALEWAY_STORAGE_CLASS = "STANDARD";
          # The job key may not create buckets; the bucket exists already.
          RCLONE_CONFIG_SCALEWAY_NO_CHECK_BUCKET = "true";
        };

        serviceConfig = hardening // {
          Type = "oneshot";
          DynamicUser = true;
          EnvironmentFile = config.sops.templates."seaweedfs-backup.env".path;
          ExecStart = lib.getExe backup;
          ExecStopPost = "+${lib.getExe backupMetrics}";
          TimeoutStartSec = "3h";
        };
      };
    };

    # After the 03:00 Postgres and MariaDB base backups. Persistent: a run missed
    # while the host was off happens at the next boot.
    timers.seaweedfs-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 04:15:00 UTC";
        Persistent = true;
      };
    };

    tmpfiles.rules = [ "d ${textfileDir} 0755 root root -" ];
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
      scaleway-backup-access-key = { };
      scaleway-backup-secret-key = { };
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

    # The admin identity reads SeaweedFS: it already lives on this host, and root
    # here can read every object anyway, so a separate read-only key buys nothing.
    templates."seaweedfs-backup.env" = {
      mode = "0400";
      content = ''
        RCLONE_CONFIG_SEAWEEDFS_ACCESS_KEY_ID=${config.sops.placeholder.seaweedfs-admin-access-key}
        RCLONE_CONFIG_SEAWEEDFS_SECRET_ACCESS_KEY=${config.sops.placeholder.seaweedfs-admin-secret-key}
        RCLONE_CONFIG_SCALEWAY_ACCESS_KEY_ID=${config.sops.placeholder.scaleway-backup-access-key}
        RCLONE_CONFIG_SCALEWAY_SECRET_ACCESS_KEY=${config.sops.placeholder.scaleway-backup-secret-key}
      '';
    };
  };

  # Scraped by the cluster's Alloy (job "s3-01"): host health plus the backup
  # result. LAN only; Cilium masquerades pod egress to the node addresses.
  services.prometheus.exporters.node = {
    enable = true;
    extraFlags = [ "--collector.textfile.directory=${textfileDir}" ];
    openFirewall = true;
    firewallFilter = "-p tcp -m tcp -s 10.82.50.0/24 --dport ${toString config.services.prometheus.exporters.node.port}";
  };

  networking.firewall.allowedTCPPorts = [ s3Port ];
}
