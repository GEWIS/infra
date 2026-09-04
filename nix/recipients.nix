{
  adminOnly = [
    "tofu"
    "talos"
    "sealed-secrets"
    "authentik"
  ];

  admins = {
    luuk = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHnm7ME9L/KuEGbSbzPJ4uVgsNl579UCCtXAIlWNYq7x";
    ruben = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDCa+5whrcPG6CADGU4PcTO+X15TwoDaEg9K/GCskGlM";
  };

  hosts = {
    pcgewisinfo = {
      key = "age1hde6y6ee9g0pnvgdluxjj6xq4plrsdq8f7mf4yv6xn465ucpw3hq47heg0";
      adminReadable = true;
    };
    pcgewisc = {
      key = "age1q4lkanpv39xp36w0symj2uulgpr924ghvl56j0rnnphcz7qxr32spk9lkc";
      adminReadable = true;
    };
    pcgewisd = {
      key = "age1xjny3erjq38f8p0yu29ag6dsgpk9y4wduhahqv3vf2uapa60gs3qxm3e06";
      adminReadable = true;
    };

    s3-01 = {
      key = "age1r9nz065avdtvrx2rqyq5lztf53dw8ds0uvkxkuw2zgvkqqx5e9js347zqu";
    };
  };
}
