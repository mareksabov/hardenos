{ config, pkgs, lib, ... }:
let
  waybarConfig = pkgs.writeText "waybar-config.jsonc" ''
    {
      "layer": "top",
      "position": "top",
      "mode": "hide",
      "height": 26,
      "modules-left": [],
      "modules-center": ["clock"],
      "modules-right": ["network", "battery"],
      "clock": { "format": "{:%H:%M  %a %d.%m}" },
      "battery": { "format": "{capacity}%", "states": { "warning": 30, "critical": 15 } },
      "network": {
        "format-wifi": "{essid} ({signalStrength}%)",
        "format-ethernet": "eth",
        "format-disconnected": "off"
      }
    }
  '';
  waybarStyle = pkgs.writeText "waybar-style.css" ''
    * { font-family: monospace; font-size: 12px; min-height: 0; }
    window#waybar { background: rgba(0,0,0,0.85); color: #ddd; }
    #clock, #network, #battery { padding: 0 10px; }
    #battery.warning { color: #e5c07b; }
    #battery.critical { color: #e06c75; }
  '';
  # waycorner: hot-edge na hornom okraji. Vstup kurzora -> SIGUSR1 (odkryje waybar),
  # odchod -> SIGUSR1 (skryje). Výška zóny = výška lišty, aby nepadala pri prejdení naň.
  waycornerConfig = pkgs.writeText "waycorner.toml" ''
    [top]
    locations = ["top"]
    size = 28
    enter_command = ["pkill", "-USR1", "-x", "waybar"]
    exit_command = ["pkill", "-USR1", "-x", "waybar"]
    timeout_ms = 0
  '';
in
{
  environment.systemPackages = [ pkgs.waybar pkgs.waycorner ];

  environment.etc."xdg/waybar/config.jsonc".source = waybarConfig;
  environment.etc."xdg/waybar/style.css".source = waybarStyle;
  environment.etc."waycorner/config.toml".source = waycornerConfig;

  environment.etc."sway/config.d/waybar.conf".text = ''
    # waybar v "hide" móde (bez rezervovaného miesta), po štarte raz skrytý.
    exec waybar
    exec sleep 1 && pkill -SIGUSR1 waybar

    # hover-reveal cez waycorner hot-edge na hornom okraji
    exec waycorner --config /etc/waycorner/config.toml

    # garantovaný fallback: $mod+b toggle viditeľnosti
    bindsym $mod+b exec pkill -SIGUSR1 waybar
  '';
}
