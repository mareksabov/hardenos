# PLACEHOLDER — NAHRAĎ obsahom vygenerovaným vo VM príkazom:
#   nixos-generate-config --root /mnt
# a skopíruj /mnt/etc/nixos/hardware-configuration.nix sem.
# Tento placeholder zodpovedá disk layoutu z Task 1, Step 1 (by-label nixos/BOOT),
# takže flake evaluuje aj pred prvým generovaním — ale na reálny boot ho prepíš.
{ lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "virtio_pci" "virtio_blk" "usbhid" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];

  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/BOOT"; fsType = "vfat"; };

  swapDevices = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
}
