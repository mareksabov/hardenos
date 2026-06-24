{ config, pkgs, lib, ... }:
{
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "Europe/Bratislava";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "us";

  users.users.marky = {
    isNormalUser = true;
    description = "Marek";
    extraGroups = [ "wheel" "video" "input" ];
    initialPassword = "changeme";
  };

  environment.systemPackages = with pkgs; [
    git
    vim
  ];

  # zram swap — komprimovaný swap v RAM. Kľúčové pre 4 GB cieľový notebook
  # (Dell Latitude E5540, i5-4200U): viac browser inštancií per-workspace
  # by inak narazilo na strop pamäte.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  system.stateVersion = "25.11";
}
