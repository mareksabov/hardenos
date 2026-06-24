{ config, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    foot
    neovim
    git
    tmux
    openssh   # ssh klient (nie server)
  ];

  environment.etc."sway/config.d/terminal.conf".text = ''
    bindsym $mod+t exec foot
  '';
}
