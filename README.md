# hardenos — Browser-Centric NixOS

Minimálny, hardened, deklaratívny NixOS, ktorý bootuje rovno do [sway](https://swaywm.org/)
s fullscreen [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium).
Web + vývoj, izolácia per-workspace, systémový adblock, auto-hide lišta. Žiadne ťažké
desktop prostredie — sway je len tenký launcher.

## Filozofia

- **Browser-first.** Po boote si rovno v prehliadači (workspace 1).
- **Hardening je prvotriedny cieľ.** `doas` namiesto `sudo`, firewall default-deny,
  sysctl hardening, žiadne zbytočné služby/daemony.
- **Deklaratívne, bez home-manager.** Celá konfigurácia (vrátane sway/waybar/foot)
  je čistý NixOS modul cez `environment.etc` a program moduly.
- **Lean.** Cieľ je bežať aj na slabom HW (Dell Latitude E5540, 4 GB RAM).

## Hosty

Jeden flake, zdieľaný modulový strom (`modules/`), dva hosty:

- `vm` — `aarch64-linux`, vývoj/testovanie v UTM na Apple Silicon.
- `laptop` — `x86_64-linux`, reálny notebook (cieľ nasadenia).

Každý modul je architektúrne nezávislý — `nix flake check` evaluuje oba hosty.

## Štruktúra

```
flake.nix                      # vstupy, nixosConfigurations (vm, laptop), devShell
modules/
  default.nix                  # agregátor — importuje všetky zdieľané moduly
  base.nix                     # nix settings, user marky, locale, systemd-boot
  hardening.nix                # doas, firewall, sysctl, vypnuté služby, nix-gc
  sway.nix                     # greetd autologin -> sway, sway config cez /etc
  browser.nix                  # ungoogled-chromium + per-workspace launcher
  terminal.nix                 # foot + neovim/git/tmux
  waybar.nix                   # auto-hide lišta (hover na hornom okraji)
  adblock.nix                  # systémový hosts blocklist (StevenBlack)
hosts/
  vm/                          # aarch64 dev host (+ hardware-configuration.nix)
  laptop/                      # x86_64 cieľ (hardware-configuration.nix placeholder)
```

## Vývojový loop (Apple Silicon / UTM)

macOS **nevie** buildovať Linux closury → build aj test prebiehajú **vo vnútri
aarch64 NixOS VM v UTM**.

### Bootstrap VM

1. V UTM vytvor **Virtualize → Linux** VM (nie Emulate): ~4 CPU, 4–8 GB RAM,
   20+ GB disk, **UEFI**.
2. **Display nastav na `virtio-gpu-pci`.** Default `virtio-ramfb` dáva čiernu
   obrazovku („Display output is not active").
3. **UTM → Display → Upscaling → Linear** (inak je text rozpixelovaný).
4. Nabootuj z [NixOS minimal aarch64 ISO](https://nixos.org/download), rozdeľ disk
   (GPT: 512M ESP `BOOT` + zvyšok ext4 `nixos`), `nixos-generate-config --root /mnt`,
   doplň minimálny `configuration.nix` (systemd-boot, flakes, user `marky`, openssh),
   `nixos-install`, `reboot`.
5. Skopíruj vygenerovaný `hardware-configuration.nix` do `hosts/vm/`.

### Iterácia (GIT loop)

Edituj na Macu → commit → push → vo VM pull → rebuild:

```bash
# na Macu
git commit -am "..."
git push

# vo VM
cd ~/os && git fetch && git reset --hard origin/main
sudo nixos-rebuild switch --flake ~/os#vm
```

> SSH na VM je zapnuté práve preto, aby sa dal použiť tento loop z Macu
> (paste do UTM konzoly nefunguje). VM IP zistíš cez `ip -4 a`.

### Display fix (UTM / virtio-gpu)

V `hosts/vm/default.nix`:
- `WLR_NO_HARDWARE_CURSORS = "1"` — inak je kurzor na zlom mieste / prevrátený.
- `output Virtual-1 mode 1920x1200` — 16:10 (pomer MacBooku); default je malé 1280×800.

## Nasadenie na notebook (x86_64)

1. Nainštaluj NixOS na notebook, spusti `nixos-generate-config`.
2. Nahraď `hosts/laptop/hardware-configuration.nix` vygenerovaným súborom.
3. `sudo nixos-rebuild switch --flake .#laptop`

## Klávesy

| Klávesa | Akcia |
|---|---|
| `Mod+Return` | browser na aktuálnom workspace (izolovaný profil podľa čísla) |
| `Mod+t` | terminál (foot) |
| `Mod+Shift+←/→` | predošlý / ďalší desktop (`→` za posledným vytvorí nový + browser) |
| `Mod+1..4` | skok na desktop 1–4 (ak číslo nové → vytvorí + browser) |
| 3-prstový swipe ←/→ | ďalší / predošlý desktop |
| `Mod+b` | toggle lišty |
| `Mod+Shift+q` | zavri okno |
| `Mod+Shift+e` | ukonči sway |

`Mod` = `Control`. (Na Macu/UTM macOS preberá Cmd/⌘ skratky — napr. Cmd+Shift+Q =
Odhlásiť sa — skôr než VM; Control sa do VM dostane vždy. Cena: Control zatieni
niektoré in-VM skratky ako browser Ctrl+T/Ctrl+1-4 a tmux Ctrl+B.) Lišta je inak
skrytá a **odkryje sa pri myši na hornom okraji** (auto-hide cez
[waycorner](https://github.com/edzdez/waycorner)).

> **Pozn.:** Po `nixos-rebuild switch`, ktorý mení sway config (klávesy), bežiaci
> sway sám nereloadne — spusti **`swaymsg reload`** (alebo sa odhlás/prihlás),
> inak ostanú staré bindingy aktívne.

## Funkcie

- **Per-workspace izolácia prehliadača** — každý workspace má vlastný
  `--user-data-dir` profil (`~/.local/share/os-browser/ws<n>`), oddelené
  sessions/cookies.
- **Systémový adblock** — [StevenBlack hosts](https://github.com/StevenBlack/hosts)
  blocklist v `/etc/hosts` (~121k domén → `0.0.0.0`), platí pre všetky inštancie
  prehliadača naraz.
- **Auto-hide lišta** — hodiny / wifi / batéria. Skrytá by default; model
  start/kill (skutočný stav = beží proces `waybar`, žiadne sledovanie premennej),
  takže hover ostáva konzistentný aj pri rýchlych pohyboch myši.
- **`vim` → neovim** — `programs.neovim` s `vi`/`vim` aliasmi a `$EDITOR=nvim`.

## Dev shell

```bash
direnv allow   # potrebuje direnv + nix-direnv; načíta `nix develop`
```

## Hardening (zhrnutie)

- `doas` (wheel group) namiesto `sudo`; `sudo` je vypnuté.
- Firewall default-deny incoming.
- `kernel.kptr_restrict=2`, `kernel.dmesg_restrict=1`, `rp_filter=1`.
- `nix-gc` automaticky maže generácie staršie než 14 dní.
- Žiadne zbytočné služby; `openssh` je default off (vm host ho zapína pre dev loop).
