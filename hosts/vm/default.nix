{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "os-vm";
  networking.networkmanager.enable = true;

  # Dev convenience (len VM, nie laptop): SSH z Macu = paste-friendly workflow.
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";
}
