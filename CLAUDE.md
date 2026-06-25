# CLAUDE.md — pokyny pre prácu na `hardenos`

Kontext pre Claude Code pri práci na tomto repe. (Lokálne dev špecifiká ako VM IP
a SSH kľúč nie sú tu — sú v Claude memory mimo repa.)

## Čo to je

`hardenos` — minimálny, hardened, deklaratívny NixOS, ktorý bootuje rovno do sway
s fullscreen ungoogled-chromium. Browser-first, per-workspace izolácia, systémový
adblock, auto-hide lišta. Cieľ: učenie + hardening, sekundárne daily driver na
slabom HW (Dell Latitude E5540, 4 GB RAM → **leanness je nutnosť, nie štýl**).

Dokumenty: dizajn `docs/superpowers/specs/2026-06-24-browser-centric-nixos-design.md`,
plán `docs/superpowers/plans/2026-06-24-browser-centric-nixos-phase1.md`.

## Stav

**Fáza 1 KOMPLETNÁ (k 2026-06-25)** — všetkých 9 taskov hotových a overených vo VM.
Reálne nasadenie na x86_64 notebook ešte NEprebehlo (`hosts/laptop/hardware-configuration.nix`
je placeholder; laptop host zatiaľ len evaluuje).

## Architektúra

Jeden flake (`nixpkgs nixos-25.11`), bez home-manager. Zdieľaný `modules/` +
dva hosty:

- `modules/{base,hardening,sway,browser,terminal,waybar,adblock}.nix` — agreguje
  `modules/default.nix`.
- `hosts/vm` = `aarch64-linux` (dev VM v UTM), `hosts/laptop` = `x86_64-linux` (cieľ).
- User `marky`, init heslo `changeme`. sway config sa píše cez `environment.etc`
  (`/etc/sway/config.d/*.conf`).

## Vývojový loop (DÔLEŽITÉ)

- **macOS NEVIE buildovať Linux closury** → build a test VŽDY vo vnútri aarch64 VM.
- **GIT loop, NIE scp:** edit na Macu → `git commit` → `git push` → vo VM
  `cd ~/os && git fetch && git reset --hard origin/main` → `sudo nixos-rebuild switch --flake ~/os#vm`.
- Flake je `git+file` → vidí len **git-tracked** súbory.
- Overenie = build + pozorovateľné správanie vo VM (žiadne unit testy).

## Konvencie a gotchy (NEZABUDNI)

- **Žiadne IFD v zdieľaných moduloch.** `builtins.readFile (pkgs.runCommand ...)`
  si vynúti build derivácie pre cieľovú architektúru pri evaluácii → x86_64 host
  sa nedá evaluovať na aarch64 VM. Filtruj/spracuj v čistom Nixe; `fetchurl` (FOD)
  má rovnaký store path na oboch archoch. Každý zdieľaný modul musí evaluovať pre
  obe architektúry bez buildu (`nix eval .#nixosConfigurations.{vm,laptop}...drvPath`).
- **Pred `git add` čítaj `.gitignore`.** NIKDY necommitnúť `*.iso` (raz nafúklo
  `.git` na 1,6 GB). Žiadne background pushe — pushuj len keď to dáva zmysel pre loop.
- **Žiadne globálne zmeny** (`git config --global`, systémové nastavenia mimo repa)
  bez výslovného súhlasu usera.
- **waybar = start/kill model.** Skutočný stav cez `pgrep` (beží = zobrazená),
  žiadne sledovanie premennej/markera (rozsynchronizuje sa). Proces je
  `.waybar-wrapped` (NixOS wrapper). Hover cez waycorner hot-edge "top".
- **UTM/virtio-gpu display:** `WLR_NO_HARDWARE_CURSORS=1` (inak prevrátený/odsadený
  kurzor), `output Virtual-1 mode 1920x1200` (16:10). Host-side: Display →
  Upscaling → Linear. Display device = `virtio-gpu-pci` (nie ramfb).
- **doas, nie sudo** (sudo je vypnuté). doas cez SSH potrebuje PTY (`ssh -t`).

## Tón

User dbá na presnosť a na to, aby sa robilo presne ako hovorí (predošlá session
zlyhala na ISO-commite a improvizácii). Byť precízny, nedeviovať, pýtať sa pri
nejasnostiach radšej než hádať.
