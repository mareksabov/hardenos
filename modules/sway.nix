{ config, pkgs, lib, ... }:
let
  swayConfig = pkgs.writeText "sway-config" ''
    # Minimal browser-centric sway config
    set $mod Mod4
    # žiadne default app launchery — appky pridajú ďalšie moduly

    # základné ovládanie
    bindsym $mod+Shift+q kill
    bindsym $mod+Shift+e exec swaymsg exit

    # workspaces (dynamické) — klávesy
    bindsym $mod+1 workspace number 1
    bindsym $mod+2 workspace number 2
    bindsym $mod+3 workspace number 3
    bindsym $mod+4 workspace number 4
    bindsym Control+Shift+Right workspace next
    bindsym Control+Shift+Left workspace prev

    # 3-prstové gestá
    bindgesture swipe:3:right workspace prev
    bindgesture swipe:3:left workspace next

    # každý browser je fullscreen; bez okrajov/titlebarov
    default_border none
    hide_edge_borders both

    include /etc/sway/config.d/*
  '';
in
{
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  environment.etc."sway/config".source = swayConfig;
  environment.etc."sway/config.d/.keep".text = "";

  # greetd: autologin -> sway na TTY1
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.sway}/bin/sway";
      user = "marky";
    };
  };

  # potrebné pre Wayland appky
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
