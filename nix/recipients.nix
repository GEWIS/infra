{
  adminOnly = [
    "tofu"
    "talos"
    "sealed-secrets"
    "authentik"
  ];

  admins = {
    luuk = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHnm7ME9L/KuEGbSbzPJ4uVgsNl579UCCtXAIlWNYq7x";
    ruben = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDZWdjw+5VujLv00Jec8xvh7OmzmmGE2sPRRAjzKt+mA";
  };

  hosts = {
    pcgewisinfo = {
      key = "age1hde6y6ee9g0pnvgdluxjj6xq4plrsdq8f7mf4yv6xn465ucpw3hq47heg0";
      adminReadable = false;
    };

    s3-01 = {
      key = "age1r9nz065avdtvrx2rqyq5lztf53dw8ds0uvkxkuw2zgvkqqx5e9js347zqu";
    };
  };
}
