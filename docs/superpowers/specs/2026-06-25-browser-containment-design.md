# Browser containment — Dizajn (Fáza 2, sub-projekt 2)

**Dátum:** 2026-06-25
**Stav:** Schválený dizajn, pred implementačným plánom.
**Kontext:** Druhý kúsok hardening roadmapy. Stavia na baseline (sub-projekt 1,
`docs/hardening.md`). Tretí kúsok: egress (nftables). Roadmapa/threat model:
brainstorm 2026-06-25.

## 1. Prečo (threat model)

Baseline sťažil RCE → kernel-escape. Tento kúsok rieši **blast radius v user-space**:
popnutý chromium beží ako user `marky`, takže dnes vidí **všetko, čo marky** —
`~/.ssh` (dev kľúč!), repo `~/os`, dotfiles, profily ostatných desktopov.

**Cieľ (potvrdené s userom): browser-from-system.** Popnutý chromium **nesmie čítať**
marky-ho tajomstvá (`~/.ssh`, `~/os`, citlivé dotfiles). Izolácia **desktop-od-desktopu**
(ws1 nevidí profil ws2) je **mimo rozsah** tohto kúsku — ostáva ako teraz (oddelené
profil dir-y, rovnaký uid).

## 2. Rozhodnutia (potvrdené s userom)

- **Mechanizmus: `bubblewrap` (bwrap, `0.11.0`)** — postaví obmedzený mount-namespace
  FS view: `tmpfs` cez `~`, do ktorého sa bind-ne len profil + nutné systémové cesty.
  `~/.ssh`/`~/os` v tom view jednoducho **neexistujú**.
  - **Prečo bwrap, nie landlock/landrun:** landlock by bol elegantnejší (on-theme,
    máme LSM zapnutý), ale `landrun` sa na aarch64 **nedá rovno použiť** (nie je
    v cache → builduje sa → jeho self-test padá v Nix build-sandboxe). Náš **jediný
    testovateľný stroj je aarch64 VM**, takže neoveriteľnú vec nenasadzujeme. bwrap je
    v cache, funguje hneď, je **battle-tested na chromium** (používa ho flatpak) a dáva
    **rovnaký výsledok**. Landlock → budúci upgrade (najmä na reálnom x86_64 Delli).
- **Fail-closed** — ak bwrap nevie nastaviť sandbox, browser sa **nespustí**. Radšej
  žiadny browser než neuzavretý.
- **Nested sandbox sa zachová** — bwrap NESMIE zablokovať chromium vlastný sandbox
  (chromium vytvára vlastné user/pid namespaces vnútri). Akceptačná brána to overí.
- **Sieť: neobmedzená** — egress je sub-projekt 3, nemiešame (bez `--unshare-net`).
- **ws-from-ws mimo rozsah** — bind-ne sa celý profil base (všetky ws).

## 3. Návrh

### Komponent: `os-browser` zabalený do `bwrap`

`os-browser <n>` (v `modules/browser.nix`) dnes spúšťa `exec chromium --user-data-dir=…`.
Po novom: `exec bwrap <bind flagy> -- chromium --user-data-dir=…`. `bubblewrap` sa pridá
do `runtimeInputs`.

### FS view (čo chromium uvidí)
| Cesta | Režim | Prečo |
|---|---|---|
| `~/.local/share/os-browser` | bind rw | profil(y) — chromium tam píše dáta |
| `~` (zvyšok) | tmpfs (prázdne) | `~/.ssh`, `~/os`, dotfiles **zmiznú** z view |
| `/nix/store`, `/run/current-system` | ro-bind | knižnice, binárky, fonty |
| `/etc` | ro-bind | resolv.conf, SSL certy, `/etc/fonts`, machine-id |
| `/run/user/1000` | bind rw | wayland socket, dbus session, pulse |
| `/proc`, `/dev` | `--proc` / `--dev` | chromium introspekcia, základné zariadenia |
| `/dev/dri`, `/dev/shm` | dev-bind / tmpfs | GPU, shared memory (chromium IPC) |
| `/sys` (podľa potreby) | ro-bind | GPU/device info |
| `/tmp` | tmpfs | dočasné |
| sieť | povolená (žiadny `--unshare-net`) | egress rieši sub-projekt 3 |

bwrap flagy navyše: `--die-with-parent`, `--unshare-pid`, zachovať možnosť nested
user namespace (žiadny flag, ktorý chromium-userns zablokuje). `HOME`,
`XDG_RUNTIME_DIR`, `WAYLAND_DISPLAY` sa nastavia/prenesú.

### Deny (pointa)
`~/.ssh`, `~/os`, `~/.gnupg`, zvyšok `~` — pre chromium a jeho child procesy
(renderery) **neexistujú** (tmpfs cez home, bind len profilu).

### Footgun a postup
Chromium siaha na veľa ciest; **bind set sa doladí iteráciou vo VM** (browser nenabehne
→ chromium error / strace ukáže chýbajúcu cestu → pridaj bind → znova). Presné bwrap
flagy sa finalizujú v pláne podľa `bwrap --help` a reálneho správania. **Kontingencia:**
ak by bwrap+chromium bol neriešiteľný (nested sandbox konflikt), prehodnotíme (landlock
na Delli, alebo systemd-run). „Však sa hráme" — keď to bude zlé, prerobí sa.

## 4. Súbory
- Modify: `modules/browser.nix` — `osBrowser`: pridať `bubblewrap` do `runtimeInputs`,
  obaliť `exec` bwrapom; fail-closed (žiadny fallback na neuzavretý chromium).
- Modify: `docs/hardening.md` — pridať sekciu „Browser containment".
- Bez zmeny: `os-workspace`, `os-empty-watcher` (volajú `os-browser`, ten ostáva).

## 5. Akceptačná brána + verifikácia (vo VM cez SSH)

Tri podmienky (všetky musia platiť):
1. **Sandbox neporušený** — chromium beží **bez** `--no-sandbox`, žiadne
   „No usable sandbox!"; reálne sa zobrazí okno.
2. **Secrety skryté** — z pohľadu browser procesu sú `~/.ssh` aj `~/os`
   **nedostupné**. Overenie: probe spustený v **rovnakom bwrap kontexte**
   (`bwrap … -- ls /home/marky/.ssh`) zlyhá / je prázdny; resp.
   `cat /proc/<chromium-pid>/root/home/marky/.ssh/*` neexistuje.
3. **Browser funguje** — okno sa zobrazí (`swaymsg` representation = `chromium-browser`)
   a vyrenderuje stránku.

Plus: `nix eval` oboch hostov bez buildu; sway/desktopy/watcher nerozbité.

## 6. Dokumentácia (prvotriedny deliverable)
- `docs/hardening.md` — nová sekcia „Browser containment": threat model (blast radius
  v user-space), FS-view/deny tabuľka, prečo bwrap (a prečo nie landlock teraz),
  ako overiť, fail-closed. Zvýrazniť, že `~/.ssh`/`~/os` sú skryté.
- Inline komentár v `os-browser` pri bwrap obale.
- README „Hardening" — pridať vetu o browser containmente + link.

## 7. Mimo rozsahu (YAGNI / odložené)
- **Landlock varianta** (landrun) — budúci upgrade, najmä na reálnom x86_64 Delli
  (kde je landrun v cache). Elegantnejšie, ale na aarch64 VM neoveriteľné.
- **Desktop-od-desktopu izolácia** (ws1 ↔ ws2 profily) — neskôr, ak vôbec.
- **Network/egress obmedzenie z browsera** — sub-projekt 3.
- Obmedzenie zariadení (kamera, USB) — neskôr.
