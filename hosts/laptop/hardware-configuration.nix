# PLACEHOLDER — nahradí výstup `nixos-generate-config` z reálneho notebooku.
{ lib, ... }:
{
  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usbhid" "sd_mod" ];
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/BOOT"; fsType = "vfat"; };
  swapDevices = [ ];
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
