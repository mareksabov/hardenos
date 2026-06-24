{ config, pkgs, lib, ... }:
{
  environment.systemPackages = with pkgs; [
    foot
    git
    tmux
    openssh   # ssh klient (nie server)
  ];

  # neovim + vim/vi aliasy (vim spustí nvim) a default $EDITOR
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
  };

  environment.etc."sway/config.d/terminal.conf".text = ''
    bindsym $mod+t exec foot
  '';
}
