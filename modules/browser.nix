{ config, pkgs, lib, ... }:
let
  # spustí chromium s profilom podľa čísla workspace (per-workspace izolácia)
  osBrowser = pkgs.writeShellApplication {
    name = "os-browser";
    runtimeInputs = [ pkgs.ungoogled-chromium ];
    text = ''
      ws="''${1:-1}"
      profile="$HOME/.local/share/os-browser/ws''${ws}"
      mkdir -p "$profile"
      exec chromium \
        --user-data-dir="$profile" \
        --ozone-platform=wayland \
        --start-maximized \
        --no-first-run \
        --no-default-browser-check
    '';
  };

  osWorkspace = pkgs.writeShellApplication {
    name = "os-workspace";
    runtimeInputs = [ pkgs.sway pkgs.jq osBrowser ];
    text = ''
      arg="''${1:-next}"
      current="$(swaymsg -t get_workspaces | jq -r '.[] | select(.focused).num')"
      case "$arg" in
        next) target=$(( current + 1 )) ;;
        prev) if [ "$current" -gt 1 ]; then target=$(( current - 1 )); else target=1; fi ;;
        *)    target="$arg" ;;
      esac
      existed="$(swaymsg -t get_workspaces | jq "any(.num == $target)")"
      swaymsg workspace number "$target"
      if [ "$existed" = "false" ]; then
        os-browser "$target"
      fi
    '';
  };
in
{
  environment.systemPackages = [ pkgs.ungoogled-chromium osBrowser osWorkspace ];

  # keybinding + autostart cez sway config.d
  environment.etc."sway/config.d/browser.conf".text = ''
    # browser na aktuálnom workspace (manuálne znovuotvorenie)
    bindsym $mod+Return exec os-browser "$(swaymsg -t get_workspaces | ${pkgs.jq}/bin/jq -r '.[] | select(.focused).num')"

    # navigácia: nekonečné dynamické desktopy, nový desktop = nový browser
    bindsym $mod+Shift+Right exec os-workspace next
    bindsym $mod+Shift+Left  exec os-workspace prev
    bindsym $mod+1 exec os-workspace 1
    bindsym $mod+2 exec os-workspace 2
    bindsym $mod+3 exec os-workspace 3
    bindsym $mod+4 exec os-workspace 4

    # 3-prstové gestá (rovnaká orientácia ako predtým)
    bindgesture swipe:3:right exec os-workspace prev
    bindgesture swipe:3:left  exec os-workspace next

    # autostart: workspace 1 dostane browser pri štarte
    exec os-browser 1
  '';
}
