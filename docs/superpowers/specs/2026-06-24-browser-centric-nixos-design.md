# Browser-Centric NixOS — Dizajn (Fáza 1)

**Dátum:** 2026-06-24
**Stav:** ✅ Implementované — Fáza 1 kompletná (k 2026-06-25). Implementačný plán: `docs/superpowers/plans/2026-06-24-browser-centric-nixos-phase1.md`. Tento dokument ostáva ako pôvodný dizajn; sekcia 10 nižšie zhŕňa, ako sa otvorené otázky reálne vyriešili.

## 1. Cieľ a filozofia

Minimálny, reprodukovateľný, hardened operačný systém na báze NixOS, ktorý
nabootuje rovno do browser-centrického prostredia. Žiadne ťažké desktop
prostredie, žiadny balast — len to, čo je naozaj potrebné.

**Priority (v poradí):**
1. **Učenie a experimentovanie** — pochopiť NixOS, Linux boot, kompozítory,
   browser sandboxing, hardening. Výsledok je bonus, proces je cieľ.
2. **Hardening** — malý attack surface, immutabilita, izolácia.
3. **Daily driver** (sekundárne) — web + vývoj na staršom notebooku, ak to
   bude dobre fungovať.

**Princípy:**
- Plne **deklaratívne** — celý OS = jeden Nix config = zároveň dokumentácia.
- **Open source** od začiatku — ktokoľvek si to reprodukuje jedným príkazom.
- Dôraz na dokumentáciu a reprodukovateľnosť.

**Realistický pohľad na bezpečnosť:** Browser je jeden z najviac útočených
kusov softvéru. Browser-only OS attack surface neodstraňuje, ale ho
**koncentruje** do browsera + sandboxu. Reálny bezpečnostný prínos preto
neprichádza z „žiadnych appiek", ale z troch vecí:
1. **Minimálny systém** — žiadne zbytočné balíky, SUID binárky, daemony.
2. **Immutabilita / deklaratívnosť** — reboot/rebuild vráti systém do známeho
   stavu; útočník nevie natrvalo nič zmeniť.
3. **Sandboxing a izolácia** — browser sandbox + oddelené profily per workspace.

## 2. Base system

- **NixOS minimal** — bez zbytočných balíkov, služieb a SUID binárok.
- **Autologin do sway** cez `greetd` (najľahší správca prihlásenia, bez GUI).
- Základný hardening: vypnuté nepotrebné daemony, firewall, neskôr systemd
  hardening jednotiek. Žiadny display manager s grafickým rozhraním.

## 3. Kompozítor — sway

Sway ako **tenký „browser-only launcher"**, nie desktop prostredie. Nakonfigurovaný
tak, že spúšťa iba browser, vždy fullscreen.

- **Dynamické workspaces** (ako macOS „spaces") — sway ich má dynamické by
  default: vznikajú keď na ne prejdeš, zanikajú keď sú prázdne. Žiadny extra
  kód, vstavané správanie.
- **Prepínanie:**
  - Klávesy — `Mod+1..n`, prípadne `Ctrl+Shift+šipky`.
  - **3-prstové gestá** na touchpade — `bindgesture swipe:3:left/right workspace prev/next`.

## 4. Browsery a izolácia

- **`ungoogled-chromium`** — Chromium bez Google telemetrie, silný sandbox,
  dobrá podpora na NixOS. (Voľba sa dá kedykoľvek zmeniť.)
- **Jedna inštancia browsera s vlastným profilom per workspace**
  (`--user-data-dir`). Workspace 1 = komunikácia, workspace 2 = editor, atď.
- **Bezpečnostný zisk:** oddelené cookies/sessions medzi priestormi —
  „komunikačný" priestor fyzicky nevidí dáta „pracovného" priestoru.

## 5. Adblock

Riešené na **úrovni systému**, nie len v browseri:
- **Systémový DNS/hosts blocklist** (StevenBlack hosts alebo lokálny DNS
  resolver s blocklistami), deklaratívne v Nixe → blokuje pre **všetky**
  inštancie browsera naraz, je súčasťou OS configu.
- **Voliteľne** uBlock Origin ako extension.

## 6. Status lišta — waybar

- Obsah: **hodiny + batéria + wifi** (praktické minimum pre laptop).
- **Auto-hide** (ako macOS):
  - Primárne: reveal **myšou na horný okraj** obrazovky — vyžaduje malý glue
    skript sledujúci pozíciu kurzora (malá Fáza-1 úloha).
  - Fallback/istota: reveal cez **modifier** (`bar { mode hide }`) — vstavané.

## 7. Vývoj / terminál

- **Natívny `foot` terminál** vo vlastnom workspace (neovim/git/ssh,
  kompilovanie).
- **Prečo nie web terminál (ttyd):** keďže máme sway, natívny terminál je
  jednoduchší, ľahší a bezpečnejší — `ttyd` by pridal bežiaci localhost server
  (ďalší attack surface + latencia). Pre hardening platí „menej bežiacich
  služieb = lepšie".

## 8. Testing & multi-host (multi-arch) stratégia

Vývoj prebieha na **M3 MacBooku Pro (aarch64)**, cieľový notebook je
**x86_64**. Riešené štruktúrou projektu:

- **Flake so zdieľanými modulmi** a dvoma hostmi:
  - `vm` → `aarch64-linux` — vývoj a testovanie vo **UTM** (virtualizované
    aarch64, svižné, skoro natívne).
  - `laptop` → `x86_64-linux` — reálny notebook, neskôr.
- Celá konfigurácia (sway, browser, waybar, users, hardening) je
  **architektúrne nezávislá a zdieľaná**. Líši sa len hŕstka host-specific
  vecí (bootloader, kernel, hardware config).
- **Nasadenie na notebook:** notebook si svoj x86_64 closure postaví **sám
  natívne** (`nixos-rebuild` z toho istého flaku) — žiadne pomalé emulované
  buildy na Macu.
- **Caveat:** `ungoogled-chromium` je veľký na build — spoliehame sa na binary
  cache (cache.nixos.org / cachix). Ak by nebol cachovaný, prvý build je
  zdĺhavý. Doriešiť v implementačnom pláne.
- **Hranica testovania v VM:** hardvérovo-špecifické správanie (GPU ovládače,
  firmware) sa overí až na reálnom železe; logika OS sa správa identicky na
  oboch architektúrach.

## 8b. Vývojárske prostredie (dev tooling)

- **Flakes** — celý projekt je flake (potvrdené, povinné). Pinované vstupy
  (`flake.lock`) = plná reprodukovateľnosť.
- **`direnv` + `nix-direnv`** — automatické načítanie dev shellu pri vstupe do
  repozitára. `.envrc` obsahuje `use flake`; `nix-direnv` cachuje shell, aby sa
  načítaval rýchlo.
- Flake vystavuje **`devShell`** s nástrojmi na prácu na projekte (formatter,
  `nixos-rebuild`/`nixos-rebuild build-vm`, lint a pod.).

## 9. Mimo rozsahu (Fáza 2 — samostatný spec)

- **Modulárne lokálne web-appky** ako náhrada natívnych potrieb (prehrávač
  videa, prehliadač fotiek, PDF…), servované z localhostu, kódené postupne.
- **Sandboxing modulov:** rootless `podman` alebo `bubblewrap`/`firejail` —
  **nie Docker** (Docker daemon beží ako root = veľký attack surface, ide proti
  hardening filozofii).

## 10. Otvorené otázky — ako sa vyriešili

- **Bootloader + disk layout:** `systemd-boot` (UEFI) pre oba hosty. VM disk = GPT
  (512M ESP `BOOT` + zvyšok ext4 `nixos`), by-label fileSystems.
- **Binary cache pre chromium:** verejná `cache.nixos.org` stačila —
  `ungoogled-chromium` sa sťahuje z cache (~128 MiB), NEkompiluje sa. Vlastný
  cachix netreba.
- **Auto-hide lišta na hover:** **waycorner** (hot-edge "top", layer-shell) volá
  helper `os-bar show/hide`, ktorý beží na **start/kill modeli** — skutočný stav =
  beží proces `waybar` (`pgrep`), žiadne sledovanie premennej. Pôvodný nápad
  (skript sledujúci pozíciu kurzora cez `swaymsg`) sa zahodil, lebo sa
  rozsynchronizovával.
- **Štruktúra flaku:** zdieľaný `modules/` (base, hardening, sway, browser,
  terminal, waybar, adblock) + `hosts/{vm,laptop}` s host-specific časťami
  (hardware, hostname). Každý zdieľaný modul musí evaluovať pre obe architektúry
  **bez buildu** (žiadne IFD — viď Task 7 v pláne).
