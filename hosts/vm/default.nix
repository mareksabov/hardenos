{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "os-vm";
  networking.networkmanager.enable = true;
}
