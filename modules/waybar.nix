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
  # Jediný zdroj pravdy o viditeľnosti waybar = stavový súbor. waybar reaguje len na
  # SIGUSR1=toggle, takže show/hide musíme robiť idempotentne podľa stavu. flock proti
  # race (waycorner môže firovať z viacerých inštancií). Proces je ".waybar-wrapped"
  # -> pkill BEZ -x (substring "waybar").
  osBar = pkgs.writeShellApplication {
    name = "os-bar";
    runtimeInputs = [ pkgs.procps pkgs.util-linux ];
    text = ''
      marker=/tmp/.waybar_shown
      action="''${1:-toggle}"
      exec 9>/tmp/.waybar.lock
      flock 9
      if [ "$action" = toggle ]; then
        if [ -e "$marker" ]; then action=hide; else action=show; fi
      fi
      case "$action" in
        show) if [ ! -e "$marker" ]; then pkill -USR1 waybar || true; touch "$marker"; fi ;;
        hide) if [ -e "$marker" ]; then pkill -USR1 waybar || true; rm -f "$marker"; fi ;;
      esac
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
    # waybar v "hide" móde (bez rezervovaného miesta). Po štarte vynútene skryjeme
    # a zosúladíme stavový súbor (štartovací stav = skrytá).
    exec waybar
    exec sleep 1 && pkill -USR1 waybar && rm -f /tmp/.waybar_shown

    # hover-reveal cez waycorner hot-edge na hornom okraji (size = výška lišty)
    exec waycorner --config /etc/waycorner/config.toml

    # fallback: $mod+b toggle (cez rovnaký helper -> bez rozsynchronizovania)
    bindsym $mod+b exec os-bar toggle
  '';
}
