{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "os-vm";
  networking.networkmanager.enable = true;

  # Dev convenience (len VM, nie laptop): SSH z Macu = paste-friendly workflow.
  services.openssh.enable = true;
  services.openssh.settings.PermitRootLogin = "yes";

  # --- UTM/virtio-gpu display quirks (len VM) ---
  # Hardvérový kurzor sa pod virtio-gpu composituje na zlé miesto / prevrátene.
  # Software kurzor (sway si ho kreslí sám) to opraví.
  environment.sessionVariables.WLR_NO_HARDWARE_CURSORS = "1";

  # Pevné 16:10 rozlíšenie (zhodný pomer s MacBookom; virtio-gpu default je malé 1280x800).
  environment.etc."sway/config.d/output.conf".text = ''
    output Virtual-1 mode 1920x1200
  '';
}
