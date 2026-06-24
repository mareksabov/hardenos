{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "os-laptop";
  networking.networkmanager.enable = true;
  # x86-specifické doplníš po `nixos-generate-config` na reálnom notebooku
}
