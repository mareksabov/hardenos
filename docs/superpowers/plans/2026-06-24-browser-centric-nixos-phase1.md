# Browser-Centric NixOS (Fáza 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **STAV (k 2026-06-25): ✅ FÁZA 1 KOMPLETNÁ — všetkých 9 taskov hotových a overených vo VM.** Build/test prebehol v aarch64 UTM VM, repo je v sync na `origin/main`. Reálne nasadenie na x86_64 notebook (Dell Latitude E5540) ešte NEprebehlo — laptop host iba evaluuje, `hardware-configuration.nix` je stále placeholder.
>
> **Odchýlky od pôvodného plánu (implementácia sa líši od textu nižšie):**
> 1. **Task 6 (waybar hover):** plánovaný `os-bar-hover` skript sledujúci pozíciu kurzora cez `swaymsg` sa NEosvedčil (rozsynchronizovával sa). Finálne riešenie = **waycorner** (hot-edge "top", layer-shell) + **start/kill model** v helperi `os-bar` (skutočný stav = beží proces `waybar` cez `pgrep`, žiadne sledovanie premennej/markera). `$mod+b` = toggle. Hover overený živo.
> 2. **Task 7 (adblock):** plánovaný IFD (`builtins.readFile (pkgs.runCommand ...)`) sa zahodil — IFD si vynucuje **build derivácie pre cieľovú architektúru** pri evaluácii, čím sa x86_64 laptop host NEDAL evaluovať na aarch64 VM. Finálne = filter v **čistom Nixe** (`splitString`/`filter`/`hasPrefix`). Pravidlo: **žiadne IFD v zdieľaných moduloch.**
> 3. **Display fix (mimo plánu):** `hosts/vm/default.nix` má `WLR_NO_HARDWARE_CURSORS=1` + `output Virtual-1 mode 1920x1200` (UTM/virtio-gpu — inak prevrátený/odsadený kurzor a zlý pomer strán). UTM host-side: Display → Upscaling → **Linear**.
> 4. **Dev loop:** GIT (nie scp/shared folder) — edit na Macu → commit → push → vo VM `git fetch && git reset --hard origin/main` → `nixos-rebuild switch`. Repo vo VM v `~/os`. SSH zapnuté na vm hoste pre tento loop.

**Goal:** Postaviť minimálny, hardened, deklaratívny NixOS, ktorý nabootuje rovno do sway s fullscreen ungoogled-chromium, per-workspace izoláciou, foot terminálom, auto-hide waybar lištou a systémovým adblockom — buildovateľný pre aarch64 VM (vývoj) aj x86_64 laptop (nasadenie).

**Architecture:** Jeden flake so zdieľaným modulovým stromom (`modules/`) a dvoma hostmi (`hosts/vm` = aarch64, `hosts/laptop` = x86_64). Konfigurácia je čisté NixOS (bez home-manager); user dotfiles (sway/waybar/foot) sa píšu deklaratívne cez `environment.etc` a program moduly. Build aj test prebiehajú **vo vnútri NixOS aarch64 VM v UTM**, lebo macOS nevie buildovať Linux closury.

**Tech Stack:** Nix flakes, NixOS `nixos-25.11`, sway (Wayland), greetd (autologin), ungoogled-chromium, foot, waybar, systemd-boot, direnv + nix-direnv.

## Global Constraints

- nixpkgs channel: `nixos-25.11` (zhodný pin v `flake.lock` pre oba hosty).
- Bootloader: **systemd-boot** (UEFI).
- **Bez home-manager** — všetka konfigurácia je čistý NixOS modul.
- Primárny user: `marky` (jeden human user); root login zakázaný cez konzolu kde sa dá.
- Cieľové systémy: `aarch64-linux` (host `vm`), `x86_64-linux` (host `laptop`). Každý modul musí byť architektúrne nezávislý — žiadne natvrdo zadrátované `system`.
- Hardening je prvotriedny cieľ: žiadne zbytočné služby, balíky ani SUID; každý pridaný daemon musí byť odôvodnený.
- Browser: `ungoogled-chromium`. Jedna inštancia + vlastný `--user-data-dir` profil per workspace.
- Všetky `nixos-rebuild` príkazy sa púšťajú **vo vnútri VM**, nie na macOS hostovi.

---

## Súborová štruktúra

```
flake.nix                      # vstupy, nixosConfigurations (vm, laptop), devShell
flake.lock                     # generovaný pin
.envrc                         # "use flake" pre direnv
.gitignore
modules/
  default.nix                  # agregátor — importuje všetky zdieľané moduly (rastie po taskoch)
  base.nix                     # nix settings, user, locale, packages, systemd-boot
  hardening.nix                # firewall, sysctl, doas, zakázané služby
  sway.nix                     # greetd autologin -> sway, sway config cez /etc
  browser.nix                  # ungoogled-chromium + per-workspace launcher skript
  terminal.nix                 # foot + dev nástroje
  waybar.nix                   # waybar config + auto-hide glue skript
  adblock.nix                  # systémový hosts blocklist
hosts/
  vm/
    default.nix                # aarch64 host-specific (importuje hardware-configuration)
    hardware-configuration.nix # GENEROVANÝ na VM počas Task 1
  laptop/
    default.nix                # x86_64 host-specific (placeholder hardware do Fázy nasadenia)
    hardware-configuration.nix # placeholder, nahradí sa reálnym z notebooku
README.md                      # ako buildovať/spúšťať (Task 9)
```

**Princíp testovania:** Pri NixOS configu nie je „unit test" cez pytest. Test = **build + pozorovateľné správanie vo VM**. Každý task končí `nixos-rebuild` buildom/switchom vo VM a konkrétnou kontrolou (príkaz + očakávaný výstup). „Red first" = stav pred implementáciou (build padne / správanie chýba); „green" = po implementácii.

---

### Task 1: Bootstrap dev VM + flake skeleton (boot do konzoly)

Postaví UTM aarch64 NixOS VM ako build/test prostredie a minimálny flake, ktorý nabootuje do textovej konzoly s autologin userom. Zlúčené setup kroky, lebo bez bežiacej VM sa nedá nič otestovať.

**Files:**
- Create: `flake.nix`
- Create: `modules/default.nix`
- Create: `modules/base.nix`
- Create: `hosts/vm/default.nix`
- Create: `hosts/vm/hardware-configuration.nix` (generovaný vo VM)
- Create: `.envrc`

**Interfaces:**
- Produces: `nixosConfigurations.vm` (aarch64) a `nixosConfigurations.laptop` (x86_64) ako flake outputs; `modules/default.nix` agregátor importovaný oboma hostmi; devShell pre darwin aj linux.

- [x] **Step 1: Nainštaluj NixOS aarch64 do UTM**

V UTM vytvor novú **Virtualize → Linux** VM (nie Emulate), priradí ~4 CPU, 4–8 GB RAM, 20+ GB disk, povol UEFI. Nabootuj z **NixOS minimal aarch64 ISO** (`https://nixos.org/download` → ARM64). Po boote z ISO:

```bash
# vo VM, z live ISO
sudo -i
# rýchle UEFI rozdelenie disku (GPT: 512M ESP + zvyšok ext4)
parted /dev/vda -- mklabel gpt
parted /dev/vda -- mkpart ESP fat32 1MiB 512MiB
parted /dev/vda -- set 1 esp on
parted /dev/vda -- mkpart primary ext4 512MiB 100%
mkfs.fat -F32 -n BOOT /dev/vda1
mkfs.ext4 -L nixos /dev/vda2
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/BOOT /mnt/boot
nixos-generate-config --root /mnt
```

- [x] **Step 2: Over že hardware-configuration vznikol a skopíruj ho do repa**

```bash
cat /mnt/etc/nixos/hardware-configuration.nix
```
Expected: súbor existuje, obsahuje `fileSystems."/"` s `by-label/nixos` a `boot.initrd.availableKernelModules`. Tento súbor neskôr nakopíruješ do `hosts/vm/hardware-configuration.nix` (cez shared folder alebo git). Pre prvý bootstrap install použiješ dočasný `/mnt/etc/nixos/configuration.nix` (default vygenerovaný) len aby si dostal bootujúci systém s `nix`, gitom a SSH; finálny config príde z flaku v Step 8.

V dočasnom `/mnt/etc/nixos/configuration.nix` pred inštaláciou zabezpeč aspoň:
```nix
{ config, pkgs, ... }:
{
  imports = [ ./hardware-configuration.nix ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  services.openssh.enable = true;
  users.users.marky = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    initialPassword = "changeme";
  };
  environment.systemPackages = [ pkgs.git pkgs.vim ];
  system.stateVersion = "25.11";
}
```
```bash
nixos-install   # nastav root heslo na výzvu
reboot
```

- [x] **Step 3: Sprístupni repo vo VM (shared folder alebo git)**

Preferované: v UTM nastav **Shared Directory** (SPICE/VirtFS) na adresár repa na Macu a vo VM ho mountni:
```bash
# vo VM
sudo mkdir -p /mnt/repo
sudo mount -t virtiofs share /mnt/repo   # názov tagu podľa UTM (často "share")
```
Fallback ak shared folder zlyhá: `git clone` repa cez SSH/GitHub do `~/os` vo VM a iteruj cez `git pull`. Pre zvyšok plánu predpokladáme, že repo je vo VM dostupné v `~/os` (symlink na `/mnt/repo` alebo klon).

- [x] **Step 4: Napíš `.envrc`**

```bash
use flake
```

- [x] **Step 5: Napíš `flake.nix`**

```nix
{
  description = "Browser-centric NixOS — minimal, hardened, browser-first OS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      mkHost = system: hostModule:
        lib.nixosSystem {
          inherit system;
          modules = [ ./modules/default.nix hostModule ];
        };
    in {
      nixosConfigurations = {
        vm = mkHost "aarch64-linux" ./hosts/vm/default.nix;
        laptop = mkHost "x86_64-linux" ./hosts/laptop/default.nix;
      };

      devShells = lib.genAttrs
        [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ]
        (system:
          let pkgs = nixpkgs.legacyPackages.${system}; in {
            default = pkgs.mkShell {
              packages = [ pkgs.nixpkgs-fmt pkgs.git ];
            };
          });
    };
}
```

- [x] **Step 6: Napíš `modules/default.nix` (zatiaľ len base)**

```nix
{
  imports = [
    ./base.nix
  ];
}
```

- [x] **Step 7: Napíš `modules/base.nix`**

```nix
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

  system.stateVersion = "25.11";
}
```

- [x] **Step 8: Napíš `hosts/vm/default.nix`**

```nix
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "os-vm";
  networking.networkmanager.enable = true;
}
```
A skopíruj reálny `hardware-configuration.nix` z `/etc/nixos/hardware-configuration.nix` (vygenerovaný v Step 1) do `hosts/vm/hardware-configuration.nix`.

- [x] **Step 9: Vytvor placeholder `hosts/laptop/` aby flake evaluoval**

`hosts/laptop/default.nix`:
```nix
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "os-laptop";
  networking.networkmanager.enable = true;
}
```
`hosts/laptop/hardware-configuration.nix` (dočasný placeholder, nahradí sa reálnym z notebooku):
```nix
{ lib, ... }:
{
  # PLACEHOLDER — nahradí výstup `nixos-generate-config` z reálneho notebooku.
  boot.loader.grub.enable = lib.mkDefault false;
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/BOOT"; fsType = "vfat"; };
  boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "usbhid" "sd_mod" ];
}
```

- [x] **Step 10: Over že flake evaluuje (red → green)**

Vo VM v `~/os`:
```bash
nix flake check --no-build
```
Expected (red, ak chýba súbor/syntax): chyba. (green): bez chýb pre oba hosty.

- [x] **Step 11: Postav a prepni VM na flake config**

```bash
sudo nixos-rebuild switch --flake ~/os#vm
```
Expected: build prejde, systém sa prepne. Po reboote sa prihlásiš ako `marky`.

- [x] **Step 12: Over autologin usera a flakes**

```bash
whoami            # marky (po prihlásení)
nix --version     # nix s flake podporou
```
Expected: user existuje, `nix` funguje.

- [x] **Step 13: Commit**

```bash
git add flake.nix flake.lock modules/default.nix modules/base.nix \
  hosts/vm/default.nix hosts/vm/hardware-configuration.nix \
  hosts/laptop/default.nix hosts/laptop/hardware-configuration.nix .envrc
git commit -m "feat: flake skeleton + vm host boots to console"
```

---

### Task 2: Base hardening modul

Pridá bezpečnostné minimum: firewall, sysctl hardening, `doas` namiesto `sudo`, vypnuté nepotrebné služby.

**Files:**
- Create: `modules/hardening.nix`
- Modify: `modules/default.nix`

**Interfaces:**
- Consumes: `users.users.marky` z `base.nix`.
- Produces: `doas` ako priv-escalation (wheel group); aktívny firewall (default deny in).

- [x] **Step 1: Napíš `modules/hardening.nix`**

```nix
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

  # Sysctl hardening
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
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
```

- [x] **Step 2: Zaregistruj modul v `modules/default.nix`**

```nix
{
  imports = [
    ./base.nix
    ./hardening.nix
  ];
}
```

- [x] **Step 3: Build (red → green)**

```bash
sudo nixos-rebuild switch --flake ~/os#vm
```
Expected: prejde. (Ak si predtým používal `ssh` na sync, prepni na shared folder — `openssh` je teraz default off.)

- [x] **Step 4: Over hardening**

```bash
doas whoami                         # root (po hesle)
sysctl kernel.dmesg_restrict        # = 1
sudo true 2>&1 || echo "sudo gone"  # sudo neexistuje
```
Expected: `doas` funguje, sysctl = 1, `sudo` chýba.

- [x] **Step 5: Commit**

```bash
git add modules/hardening.nix modules/default.nix
git commit -m "feat: base hardening (doas, firewall, sysctl)"
```

---

### Task 3: sway + greetd autologin

Nabootuje rovno do sway (zatiaľ prázdny). greetd spraví autologin a spustí sway.

**Files:**
- Create: `modules/sway.nix`
- Modify: `modules/default.nix`

**Interfaces:**
- Consumes: `users.users.marky`.
- Produces: bežiaci sway na TTY1 po boote; sway config v `/etc/sway/config`; env premenná `SWAYSOCK` dostupná pre neskoršie skripty.

- [x] **Step 1: Napíš `modules/sway.nix`**

```nix
{ config, pkgs, lib, ... }:
let
  swayConfig = pkgs.writeText "sway-config" ''
    # Minimal browser-centric sway config
    set $mod Mod4
    # žiadne default app launchery — appky pridajú ďalšie moduly

    # základné ovládanie
    bindsym $mod+Shift+q kill
    bindsym $mod+Shift+e exec swaymsg exit

    # workspaces (dynamické) — klávesy
    bindsym $mod+1 workspace number 1
    bindsym $mod+2 workspace number 2
    bindsym $mod+3 workspace number 3
    bindsym $mod+4 workspace number 4
    bindsym Control+Shift+Right workspace next
    bindsym Control+Shift+Left workspace prev

    # 3-prstové gestá
    bindgesture swipe:3:right workspace prev
    bindgesture swipe:3:left workspace next

    # každý browser je fullscreen; bez okrajov/titlebarov
    default_border none
    hide_edge_borders both

    include /etc/sway/config.d/*
  '';
in
{
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  environment.etc."sway/config".source = swayConfig;
  environment.etc."sway/config.d/.keep".text = "";

  # greetd: autologin -> sway na TTY1
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.sway}/bin/sway";
      user = "marky";
    };
  };

  # potrebné pre Wayland appky
  environment.sessionVariables.NIXOS_OZONE_WL = "1";
}
```

- [x] **Step 2: Zaregistruj modul**

```nix
{
  imports = [
    ./base.nix
    ./hardening.nix
    ./sway.nix
  ];
}
```

- [x] **Step 3: Build a reboot (red → green)**

Red (pred): po boote textová konzola. Green (po):
```bash
sudo nixos-rebuild switch --flake ~/os#vm
reboot
```
Expected po reboote: čierna sway obrazovka (prázdna, bez appiek) namiesto konzoly.

- [x] **Step 4: Over že sway beží**

V sway otvor TTY (`Ctrl+Alt+F2`), prihlás sa a:
```bash
pgrep -a sway
ls $XDG_RUNTIME_DIR/sway-ipc.* 2>/dev/null || echo "check SWAYSOCK in session"
```
Expected: sway proces beží pre `marky`.

- [x] **Step 5: Commit**

```bash
git add modules/sway.nix modules/default.nix
git commit -m "feat: boot straight into sway via greetd autologin"
```

---

### Task 4: ungoogled-chromium + per-workspace launcher

Pridá browser a skript, ktorý na danom workspace spustí chromium s vlastným izolovaným profilom; workspace 1 sa naplní automaticky pri štarte.

**Files:**
- Create: `modules/browser.nix`
- Modify: `modules/default.nix`

**Interfaces:**
- Consumes: sway IPC (`swaymsg`), `$XDG_CURRENT_DESKTOP`.
- Produces: príkaz `os-browser <n>` (na PATH), ktorý otvorí chromium s profilom `~/.local/share/os-browser/ws<n>`; keybindings `$mod+Return` (browser na aktuálnom ws) a autostart na ws1.

- [x] **Step 1: Napíš `modules/browser.nix`**

```nix
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
```

- [x] **Step 2: Zaregistruj modul**

```nix
{
  imports = [
    ./base.nix
    ./hardening.nix
    ./sway.nix
    ./browser.nix
  ];
}
```

- [x] **Step 3: Build (red → green)**

Red: prázdny sway. Green:
```bash
sudo nixos-rebuild switch --flake ~/os#vm
reboot
```
Expected po reboote: workspace 1 sa otvorí s fullscreen chromium.

- [x] **Step 4: Over izoláciu profilov**

`$mod+2` (prepni na ws2), `$mod+Return` (otvor browser tam). Potom z TTY:
```bash
ls ~/.local/share/os-browser/
```
Expected: existujú samostatné adresáre `ws1` a `ws2` → oddelené profily/sessions.

- [x] **Step 5: Commit**

```bash
git add modules/browser.nix modules/default.nix
git commit -m "feat: per-workspace isolated chromium launcher"
```

---

### Task 5: foot terminál + dev nástroje

Pridá natívny terminál a vývojárske nástroje s keybindingom.

**Files:**
- Create: `modules/terminal.nix`
- Modify: `modules/default.nix`

**Interfaces:**
- Consumes: sway keybinding mechanizmus.
- Produces: `foot` na PATH; keybinding `$mod+t` otvorí terminál; dostupné `neovim`, `git`, `tmux`.

- [x] **Step 1: Napíš `modules/terminal.nix`**

```nix
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
```

- [x] **Step 2: Zaregistruj modul**

```nix
{
  imports = [
    ./base.nix
    ./hardening.nix
    ./sway.nix
    ./browser.nix
    ./terminal.nix
  ];
}
```

- [x] **Step 3: Build (red → green)**

```bash
sudo nixos-rebuild switch --flake ~/os#vm
```
Red pred: `$mod+t` nič. Green po: `$mod+t` otvorí foot.

- [x] **Step 4: Over terminál a gestá**

V sway stlač `$mod+t` → otvorí sa foot. V ňom:
```bash
nvim --version | head -1
git --version
```
Expected: oba nástroje fungujú. Otestuj aj 3-prstový swipe (ak UTM prepošle touchpad gestá) alebo `Ctrl+Shift+Right` → prepne workspace.

- [x] **Step 5: Commit**

```bash
git add modules/terminal.nix modules/default.nix
git commit -m "feat: foot terminal + dev tooling"
```

---

### Task 6: waybar + auto-hide na hover

Pridá tenkú lištu s hodinami/batériou/wifi, skrytú by default, ktorá sa odkryje pri myši na hornom okraji.

**Files:**
- Create: `modules/waybar.nix`
- Modify: `modules/default.nix`

**Interfaces:**
- Consumes: sway IPC; waybar príjma signál `SIGUSR1` na toggle viditeľnosti.
- Produces: waybar spustený zo sway; glue skript `os-bar-hover`, ktorý sleduje Y pozíciu kurzora a togluje lištu.

- [x] **Step 1: Napíš `modules/waybar.nix`**

```nix
{ config, pkgs, lib, ... }:
let
  waybarConfig = pkgs.writeText "waybar-config.jsonc" ''
    {
      "layer": "top",
      "position": "top",
      "height": 26,
      "modules-left": [],
      "modules-center": ["clock"],
      "modules-right": ["network", "battery"],
      "clock": { "format": "{:%H:%M  %a %d.%m}" },
      "battery": { "format": "{capacity}% {icon}", "format-icons": ["", "", "", "", ""] },
      "network": { "format-wifi": "{essid} ", "format-ethernet": "eth ", "format-disconnected": "off " }
    }
  '';
  waybarStyle = pkgs.writeText "waybar-style.css" ''
    * { font-family: monospace; font-size: 12px; }
    window#waybar { background: rgba(0,0,0,0.85); color: #ddd; }
  '';
  # glue: keď je kurzor v hornom 3px páse, ukáž lištu; inak skry.
  # waybar v "mode hide" reaguje na SIGUSR1 (toggle).
  barHover = pkgs.writeShellApplication {
    name = "os-bar-hover";
    runtimeInputs = [ pkgs.sway pkgs.jq pkgs.procps ];
    text = ''
      shown=0
      while true; do
        y=$(swaymsg -t get_seats | jq -r '.[0].name' >/dev/null 2>&1; \
            swaymsg -t get_tree | jq -r 'recurse(.nodes[]?,.floating_nodes[]?) | .' >/dev/null 2>&1; echo "")
        # pozícia kurzora cez swaymsg get_seats (cursor)
        cy=$(swaymsg -t get_seats | jq -r '.[0].cursor.pos.y // empty' 2>/dev/null || echo "")
        if [ -z "$cy" ]; then cy=$(swaymsg -t get_pointer 2>/dev/null | jq -r '.y // 999' || echo 999); fi
        if [ "''${cy%.*}" -le 3 ] 2>/dev/null; then
          if [ "$shown" -eq 0 ]; then pkill -SIGUSR1 waybar || true; shown=1; fi
        else
          if [ "$shown" -eq 1 ]; then pkill -SIGUSR1 waybar || true; shown=0; fi
        fi
        sleep 0.2
      done
    '';
  };
in
{
  environment.systemPackages = [ pkgs.waybar barHover pkgs.jq ];

  environment.etc."xdg/waybar/config.jsonc".source = waybarConfig;
  environment.etc."xdg/waybar/style.css".source = waybarStyle;

  environment.etc."sway/config.d/waybar.conf".text = ''
    # waybar spustený skrytý; glue skript ho odkrýva na hover
    exec waybar
    # po štarte skry (mode hide cez SIGUSR1 toggle z viditeľného stavu)
    exec sleep 1 && pkill -SIGUSR1 waybar
    exec os-bar-hover
    # fallback: modifier reveal
    bindsym $mod+b exec pkill -SIGUSR1 waybar
  '';
}
```

> **Pozn. pre implementátora:** presný spôsob čítania pozície kurzora cez `swaymsg` over vo VM — API sa medzi verziami sway líši (`get_seats[].cursor.pos` vs iné). Ak hover-reveal nefunguje spoľahlivo, ponechaj funkčný `$mod+b` modifier-reveal (Step 4) ako akceptované minimum a hover dolaď ako samostatný commit. Toto je jediná časť plánu so známou neistotou.

- [x] **Step 2: Zaregistruj modul**

```nix
{
  imports = [
    ./base.nix
    ./hardening.nix
    ./sway.nix
    ./browser.nix
    ./terminal.nix
    ./waybar.nix
  ];
}
```

- [x] **Step 3: Build (red → green)**

```bash
sudo nixos-rebuild switch --flake ~/os#vm
reboot
```
Expected: lišta je skrytá; objaví sa pri kurzore na hornom okraji (alebo `$mod+b`).

- [x] **Step 4: Over lištu**

Stlač `$mod+b` → lišta sa zobrazí s hodinami/batériou/wifi. Pohni myšou hore → reveal; dole → skryje sa.
Expected: aspoň `$mod+b` reveal funguje vždy; hover reveal funguje ak swaymsg API sedí.

- [x] **Step 5: Commit**

```bash
git add modules/waybar.nix modules/default.nix
git commit -m "feat: auto-hide waybar (clock/battery/wifi)"
```

---

### Task 7: Systémový adblock

Pridá hosts-based blocklist na úrovni systému — platí pre všetky inštancie browsera naraz.

**Files:**
- Create: `modules/adblock.nix`
- Modify: `modules/default.nix`

**Interfaces:**
- Consumes: nič (systémová sieťová vrstva).
- Produces: `networking.extraHosts` naplnené StevenBlack blocklistom; známe ad domény rezolvujú na `0.0.0.0`.

- [x] **Step 1: Napíš `modules/adblock.nix`**

```nix
{ config, pkgs, lib, ... }:
let
  # StevenBlack hosts (hosts-format blocklist). Hash/url over a aktualizuj podľa potreby.
  stevenblack = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/StevenBlack/hosts/3.14.139/hosts";
    # nahraď reálnym hashom: `nix store prefetch-file <url>` vo VM
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
in
{
  # extrahuj len 0.0.0.0 riadky a vlož ich do /etc/hosts deklaratívne
  networking.extraHosts = builtins.readFile (pkgs.runCommand "blocklist-hosts" { } ''
    grep '^0\.0\.0\.0 ' ${stevenblack} > $out || true
  '');
}
```

- [x] **Step 2: Zaregistruj modul**

```nix
{
  imports = [
    ./base.nix
    ./hardening.nix
    ./sway.nix
    ./browser.nix
    ./terminal.nix
    ./waybar.nix
    ./adblock.nix
  ];
}
```

- [x] **Step 3: Získaj reálny hash a build (red → green)**

Red (pred): placeholder hash → build padne s „hash mismatch", výpis ukáže reálny `got:`. Skopíruj `got:` hash do `hash = ...` a:
```bash
sudo nixos-rebuild switch --flake ~/os#vm
```
Expected po oprave hashu: build prejde.

- [x] **Step 4: Over blokovanie**

```bash
grep -c '^0\.0\.0\.0 ' /etc/hosts          # tisíce riadkov
getent hosts doubleclick.net               # 0.0.0.0
```
Expected: `/etc/hosts` obsahuje blocklist; známa ad doména rezolvuje na `0.0.0.0`.

- [x] **Step 5: Commit**

```bash
git add modules/adblock.nix modules/default.nix
git commit -m "feat: system-wide hosts adblock (StevenBlack)"
```

---

### Task 8: Laptop host + flake check oboch architektúr

Doladí x86_64 host tak, aby flake evaluoval a buildol pre obe architektúry (laptop closure sa reálne postaví až na notebooku).

**Files:**
- Modify: `hosts/laptop/default.nix`
- Modify: `flake.nix` (ak treba `formatter` output — voliteľné)

**Interfaces:**
- Consumes: `modules/default.nix` (zdieľané so `vm`).
- Produces: `nixosConfigurations.laptop` evaluuje a `nix flake check` prejde pre oba hosty.

- [x] **Step 1: Doplň `hosts/laptop/default.nix`**

```nix
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];
  networking.hostName = "os-laptop";
  networking.networkmanager.enable = true;
  # x86-specifické doplníš po `nixos-generate-config` na reálnom notebooku
}
```

- [x] **Step 2: Over evaluáciu oboch hostov (red → green)**

```bash
nix flake check
nix eval .#nixosConfigurations.laptop.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.vm.config.system.build.toplevel.drvPath
```
Expected: obe `nix eval` vrátia drv cestu (config evaluuje pre obe architektúry). `nix flake check` bez chýb.

> **Pozn.:** Reálny x86_64 build (`nixos-rebuild build --flake .#laptop`) sa spustí až na notebooku po nainštalovaní NixOS a nahradení placeholder `hardware-configuration.nix` reálnym výstupom `nixos-generate-config`. Vo VM (aarch64) sa x86_64 closure plne nestavia.

- [x] **Step 3: Commit**

```bash
git add hosts/laptop/default.nix flake.nix
git commit -m "feat: laptop host evaluates for x86_64"
```

---

### Task 9: README + dokumentácia reprodukcie

Open-source projekt potrebuje, aby si to ktokoľvek rozchodil. Zdokumentuj setup a iteračný loop.

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: celý repo.
- Produces: `README.md` s reprodukovateľnými krokmi.

- [x] **Step 1: Napíš `README.md`**

```markdown
# Browser-Centric NixOS

Minimálny, hardened, deklaratívny NixOS, ktorý bootuje rovno do sway s
fullscreen ungoogled-chromium. Web + vývoj, izolácia per-workspace, systémový
adblock. Žiadne ťažké desktop prostredie.

## Hosty
- `vm` — aarch64, vývoj/testovanie vo UTM na Apple Silicon.
- `laptop` — x86_64, reálny notebook.

## Vývojový loop (Apple Silicon)
macOS nevie buildovať Linux closury. Build aj test prebiehajú **vo vnútri
NixOS aarch64 VM v UTM**:
1. Nainštaluj NixOS aarch64 do UTM (Virtualize → Linux, UEFI).
2. Sprístupni tento repo vo VM (UTM Shared Directory alebo `git clone`).
3. `sudo nixos-rebuild switch --flake ~/os#vm`

## Nasadenie na notebook (x86_64)
1. Nainštaluj NixOS na notebook, spusti `nixos-generate-config`.
2. Nahraď `hosts/laptop/hardware-configuration.nix` vygenerovaným súborom.
3. `sudo nixos-rebuild switch --flake .#laptop`

## Klávesy
- `Mod+Return` — browser (izolovaný profil podľa workspace)
- `Mod+t` — terminál (foot)
- `Mod+1..4`, `Ctrl+Shift+←/→`, 3-prstový swipe — workspaces
- `Mod+b` — toggle lišty (inak auto-hide na hornom okraji)

## Dev shell
`direnv allow` (potrebuje direnv + nix-direnv) načíta `nix develop`.
```

- [x] **Step 2: Over že README sedí s realitou**

Prejdi klávesy v README oproti `modules/sway.nix`, `browser.nix`, `terminal.nix`, `waybar.nix`.
Expected: každá zmienená klávesa existuje v configu.

- [x] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: reproduction guide and keybindings"
```

---

## Self-Review

**Spec coverage:**
- §1 filozofia → Task 1–2 (minimal, deklaratívne) ✓
- §2 base + greetd autologin → Task 1 (autologin), Task 3 (greetd→sway) ✓
- §3 sway, dynamické ws, gestá → Task 3 ✓
- §4 ungoogled-chromium, per-ws izolácia → Task 4 ✓
- §5 systémový adblock → Task 7 ✓
- §6 waybar clock/battery/wifi + auto-hide → Task 6 ✓
- §7 foot terminál → Task 5 ✓
- §8 multi-host/multi-arch flake → Task 1 (skeleton), Task 8 (laptop eval) ✓
- §8b flakes + direnv → Task 1 (`.envrc`, flake, devShell) ✓
- §9 Fáza 2 → zámerne mimo rozsahu ✓

**Placeholder scan:** Jediné zámerné neistoty sú označené pozn. pre implementátora: (a) waybar hover-reveal swaymsg API — má funkčný fallback `$mod+b`; (b) `hardware-configuration.nix` sa generuje na reálnom HW; (c) adblock hash sa doplní z build erroru. Žiadne „TODO/implement later" bez konkrétneho postupu.

**Type consistency:** `os-browser <n>` konzistentne v Task 4 (definícia) aj README (Task 9). Workspace keybindings (`$mod+1..4`, `Ctrl+Shift+←/→`, swipe) konzistentné medzi sway.conf (Task 3) a README. `modules/default.nix` agregátor rastie monotónne, každý task pridá presne jeden import.

---

## Execution Handoff

Po uložení plánu — dve možnosti exekúcie. (Pozn.: keďže build/test beží vo VM, „subagent per task" funguje len ak subagent vie spúšťať príkazy vo VM; inak je inline s tebou pri klávesnici praktickejšie.)
