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
  # waycorner: hot-edge na hornom okraji. Vstup kurzora -> odkryje waybar, odchod -> skryje.
  # Výška zóny = výška lišty, aby nepadala pri prejdení naň. Stavový súbor robí logiku
  # idempotentnou (žiadne rozsynchronizovanie pri viacerých enter/leave po sebe).
  # POZN.: proces je ".waybar-wrapped" (NixOS wrapper) -> pkill BEZ -x (substring).
  waycornerConfig = pkgs.writeText "waycorner.toml" ''
    [top]
    locations = ["top"]
    size = 28
    enter_command = ["sh", "-c", "[ -e /tmp/.waybar_shown ] || pkill -USR1 waybar; touch /tmp/.waybar_shown"]
    exit_command = ["sh", "-c", "[ -e /tmp/.waybar_shown ] && pkill -USR1 waybar; rm -f /tmp/.waybar_shown"]
    timeout_ms = 0
  '';
in
{
  environment.systemPackages = [ pkgs.waybar pkgs.waycorner ];

  environment.etc."xdg/waybar/config.jsonc".source = waybarConfig;
  environment.etc."xdg/waybar/style.css".source = waybarStyle;
  environment.etc."waycorner/config.toml".source = waycornerConfig;

  environment.etc."sway/config.d/waybar.conf".text = ''
    # waybar v "hide" móde (bez rezervovaného miesta), po štarte raz skrytý
    # (a vyčistíme stavový súbor -> štartovací stav = skrytá).
    exec waybar
    exec sleep 1 && pkill -USR1 waybar && rm -f /tmp/.waybar_shown

    # hover-reveal cez waycorner hot-edge na hornom okraji
    exec waycorner --config /etc/waycorner/config.toml

    # garantovaný fallback: $mod+b toggle viditeľnosti
    bindsym $mod+b exec pkill -USR1 waybar
  '';
}
