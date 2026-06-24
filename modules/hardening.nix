{ config, pkgs, lib, ... }:
{
  # doas namiesto sudo — menší SUID povrch
  security.sudo.enable = false;
  security.doas = {
    enable = true;
    extraRules = [{
      groups = [ "wheel" ];
      keepEnv = true;
      persist = true;
    }];
  };

  # Firewall: default deny incoming
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };

  # Sysctl hardening
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
  };

  # Nepotrebné služby preč
  services.openssh.enable = lib.mkDefault false;
  documentation.nixos.enable = false;

  # Automatické čistenie starých generácií
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 14d";
  };
}
