{ config, pkgs, lib, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "Europe/Bratislava";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  users.users.mareks = {
    isNormalUser = true;
    description = "Marek";
    extraGroups = [ "wheel" "video" "input" ];
    initialPassword = "changeme";
  };

  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  system.stateVersion = "25.11";
}
