{ config, pkgs, lib, ... }:
let
  waybarConfig = pkgs.writeText "waybar-config.jsonc" ''
    {
      "layer": "top",
      "position": "top",
      "exclusive": false,
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
  # START/KILL model: skutočný stav = beží waybar proces? (pgrep). Žiadne sledovanie
  # stavu, ktoré by sa mohlo rozísť s realitou — akcia vždy vychádza zo skutočnosti.
  # waybar je "exclusive": false -> prekrýva obsah bez rezervovania miesta (žiadny
  # resize okien pri reveale). flock serializuje súbežné volania (waycorner môže firnúť
  # rýchlo). Proces je ".waybar-wrapped" (NixOS wrapper).
  osBar = pkgs.writeShellApplication {
    name = "os-bar";
    runtimeInputs = [ pkgs.procps pkgs.util-linux pkgs.coreutils pkgs.waybar ];
    text = ''
      action="''${1:-toggle}"
      exec 9>/tmp/.waybar.lock
      flock 9

      running=0
      if pgrep -x .waybar-wrapped >/dev/null 2>&1 || pgrep -x waybar >/dev/null 2>&1; then
        running=1
      fi

      if [ "$action" = "toggle" ]; then
        if [ "$running" -eq 1 ]; then action="hide"; else action="show"; fi
      fi

      if [ "$action" = "show" ]; then
        if [ "$running" -eq 0 ]; then
          # fd 9 zavrieme v dieťati, nech nedrží zámok
          nohup waybar >/dev/null 2>&1 9>&- &
        fi
      elif [ "$action" = "hide" ]; then
        pkill -x .waybar-wrapped >/dev/null 2>&1 || true
        pkill -x waybar >/dev/null 2>&1 || true
      fi
    '';
  };
  waycornerConfig = pkgs.writeText "waycorner.toml" ''
    [top]
    locations = ["top"]
    size = 28
    enter_command = ["os-bar", "show"]
    exit_command = ["os-bar", "hide"]
    timeout_ms = 0
  '';
in
{
  environment.systemPackages = [ pkgs.waybar pkgs.waycorner osBar ];

  environment.etc."xdg/waybar/config.jsonc".source = waybarConfig;
  environment.etc."xdg/waybar/style.css".source = waybarStyle;
  environment.etc."waycorner/config.toml".source = waycornerConfig;

  environment.etc."sway/config.d/waybar.conf".text = ''
    # waybar sa NEspúšťa pri štarte (skrytá = nebeží). Objaví sa až na hover.
    exec waycorner --config /etc/waycorner/config.toml

    # fallback: $mod+b toggle (start/kill cez rovnaký helper)
    bindsym $mod+b exec os-bar toggle
  '';
}
