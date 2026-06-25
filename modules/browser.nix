{ config, pkgs, lib, ... }:
let
  # spustí chromium s profilom podľa čísla workspace (per-workspace izolácia)
  osBrowser = pkgs.writeShellApplication {
    name = "os-browser";
    runtimeInputs = [ pkgs.ungoogled-chromium pkgs.bubblewrap ];
    text = ''
      ws="''${1:-1}"
      base="$HOME/.local/share/os-browser"
      profile="$base/ws''${ws}"
      mkdir -p "$profile"
      # bubblewrap: tmpfs cez $HOME → ~/.ssh, ~/os a dotfiles ZMIZNÚ z view;
      # bind-ne sa len profil + nutné systémové cesty. chromium si VNÚTRI vytvorí
      # vlastný namespace sandbox (potrebuje allowUserNamespaces=true z baseline).
      # fail-closed: ak bwrap zlyhá, exec zlyhá a browser sa nespustí.
      exec bwrap \
        --ro-bind /nix/store /nix/store \
        --ro-bind /run/current-system /run/current-system \
        --ro-bind /etc /etc \
        --ro-bind /sys /sys \
        --ro-bind-try /run/opengl-driver /run/opengl-driver \
        --ro-bind-try /run/dbus /run/dbus \
        --proc /proc \
        --dev /dev \
        --dev-bind-try /dev/dri /dev/dri \
        --tmpfs /tmp \
        --tmpfs /dev/shm \
        --tmpfs "$HOME" \
        --bind "$base" "$base" \
        --bind /run/user/1000 /run/user/1000 \
        --die-with-parent \
        --unshare-pid \
        chromium \
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
      existed="$(swaymsg -t get_workspaces | jq "any(.[]; .num == $target)")"
      swaymsg workspace number "$target"
      if [ "$existed" = "false" ]; then
        os-browser "$target"
      fi
    '';
  };

  # keď sa fokusnutý desktop vyprázdni (zavreté posledné okno), prepni na predošlý
  # existujúci → prázdny zanikne. Posledný/jediný desktop nechaj prázdny (macOS model).
  # Sway nemá deklaratívny hook → tenký listener na IPC window eventoch.
  osEmptyWatcher = pkgs.writeShellApplication {
    name = "os-empty-watcher";
    runtimeInputs = [ pkgs.sway pkgs.jq ];
    text = ''
      swaymsg -t subscribe -m '["window"]' | while read -r ev; do
        [ "$(jq -r '.change // empty' <<<"$ev")" = "close" ] || continue
        wins="$(swaymsg -t get_tree | jq '
          [ recurse(.nodes[]?, .floating_nodes[]?) | select(.type=="workspace" and .focused==true) ][0]
          | [ recurse(.nodes[]?, .floating_nodes[]?) | select(.type=="con" and .pid != null) ] | length
        ' 2>/dev/null || echo 1)"
        total="$(swaymsg -t get_workspaces | jq 'length' 2>/dev/null || echo 1)"
        if [ "$wins" = "0" ] && [ "$total" -gt 1 ]; then
          swaymsg workspace prev >/dev/null
        fi
      done
    '';
  };
in
{
  environment.systemPackages = [ pkgs.ungoogled-chromium osBrowser osWorkspace osEmptyWatcher ];

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

    # watcher: vyprázdnený desktop → prepni preč → zanikne (spustí sa raz pri štarte)
    exec os-empty-watcher
  '';
}
