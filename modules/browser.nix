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
in
{
  environment.systemPackages = [ pkgs.ungoogled-chromium osBrowser ];

  # keybinding + autostart cez sway config.d
  environment.etc."sway/config.d/browser.conf".text = ''
    # otvor browser (profil podľa čísla aktuálneho workspace) na aktuálnom ws
    bindsym $mod+Return exec os-browser "$(swaymsg -t get_workspaces | ${pkgs.jq}/bin/jq -r '.[] | select(.focused).num')"

    # autostart: workspace 1 dostane browser pri štarte
    exec os-browser 1
  '';
}
