{ config, pkgs, lib, ... }:
{
  # doas namiesto sudo — menší SUID povrch
  security.sudo.enable = false;
  security.doas = {
    enable = true;
    extraRules = [{
      groups = [ "wheel" ];
      keepEnv = true;
      persist = true;
    }];
  };

  # Firewall: default deny incoming
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ ];
    allowedUDPPorts = [ ];
  };

  # Chromium namespace sandbox potrebuje unprivileged user namespaces. NEvypínať
  # (to robí hardened profil) — inak chromium spadne na --no-sandbox = horšie.
  # Držíme explicitne zapnuté ako deklaratívnu poistku zámeru.
  security.allowUserNamespaces = true;

  # Sysctl hardening — všetko browser-safe (nerozbíja chromium sandbox).
  boot.kernel.sysctl = {
    # už existujúce
    "kernel.kptr_restrict" = 2;                  # skry kernel pointery z /proc
    "kernel.dmesg_restrict" = 1;                 # obmedz čítanie kernel logu
    "net.ipv4.conf.all.rp_filter" = 1;           # anti-spoof (reverse path filter)
    "net.ipv4.conf.default.rp_filter" = 1;

    # A. pamäť / proces izolácia
    "kernel.yama.ptrace_scope" = 1;              # proces neptrace-uje cudzie procesy
    "kernel.unprivileged_bpf_disabled" = 1;      # zatvor unpriv eBPF exploit vektor
    "net.core.bpf_jit_harden" = 2;               # sťaž BPF JIT-spray
    "kernel.perf_event_paranoid" = 2;            # žiadny unpriv perf (mainline max)
    "kernel.kexec_load_disabled" = 1;            # žiadny load kernelu za behu (kexec)
    "vm.unprivileged_userfaultfd" = 0;           # odober UAF-exploit techniku
    "dev.tty.ldisc_autoload" = 0;                # nezavádzaj ldisc moduly on-demand
    "fs.protected_symlinks" = 1;                 # symlink TOCTOU
    "fs.protected_hardlinks" = 1;                # hardlink TOCTOU
    "fs.protected_fifos" = 2;                    # zápis do cudzích fifo v sticky dir
    "fs.protected_regular" = 2;                  # zápis do cudzích súborov v sticky dir
    "fs.suid_dumpable" = 0;                      # SUID proc nevypíše core

    # B. sieť (anti-spoof / anti-redirect)
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv4.conf.all.secure_redirects" = 0;
    "net.ipv4.conf.default.secure_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
    "net.ipv4.conf.default.send_redirects" = 0;
    "net.ipv4.conf.all.accept_source_route" = 0;
    "net.ipv4.conf.default.accept_source_route" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv6.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_source_route" = 0;
    "net.ipv6.conf.default.accept_source_route" = 0;
    "net.ipv4.conf.all.log_martians" = 1;        # loguj spoofnuté pakety
    "net.ipv4.tcp_syncookies" = 1;               # SYN-flood ochrana
    "net.ipv4.icmp_echo_ignore_broadcasts" = 1;  # neodpovedaj na broadcast ping
  };

  # Nepotrebné služby preč
  services.openssh.enable = lib.mkDefault false;
  documentation.nixos.enable = false;

  # Automatické čistenie starých generácií
  nix.gc = {
    automatic = true;
    options = "--delete-older-than 14d";
  };
}
