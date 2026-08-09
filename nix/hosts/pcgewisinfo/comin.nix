{ ... }:

let
  gitUrl = "https://github.com/GEWIS/infra.git";
in
{
  services.comin = {
    enable = true;
    remotes = [
      {
        name = "origin";
        url = gitUrl;
        branches.main.name = "main";
      }
    ];
  };
}
