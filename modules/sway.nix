{ config, pkgs, lib, ... }:
let
  swayConfig = pkgs.writeText "sway-config" ''
    # Minimal browser-centric sway config
    # $mod = Mod1 (Alt / Option ⌥ na Macu): na Macu/UTM macOS preberá Cmd (⌘=Super)
    # skratky (napr. Cmd+Shift+Q = Odhlásiť sa) skôr než VM. Alt sa do VM dostane vždy
    # a — narozdiel od Control — nezatieni browser Ctrl+T/Ctrl+1-4 ani tmux Ctrl+B.
    # Browser back/forward (Alt+←/→) ostáva, lebo desktopy idú cez Alt+Shift+←/→.
    set $mod Mod1
    # žiadne default app launchery — appky pridajú ďalšie moduly

    # základné ovládanie
    bindsym $mod+Shift+q kill
    bindsym $mod+Shift+e exec swaymsg exit

    # workspace navigácia žije v browser.nix (browser-per-workspace)

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
