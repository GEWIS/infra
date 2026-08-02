{
  config,
  lib,
  pkgs,
  ...
}:
{
  users.motdFile =
    pkgs.runCommand "motd-${config.networking.hostName}"
      {
        nativeBuildInputs = [ pkgs.figlet ];
      }
      ''
        {
          echo
          printf '\033[38;2;212;0;38m'
          figlet -f standard ${lib.escapeShellArg config.networking.hostName}
          printf '\033[0m\n'
        } > "$out"
      '';
}
