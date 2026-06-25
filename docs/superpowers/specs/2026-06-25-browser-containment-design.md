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

- **Mechanizmus: landlock allowlist cez `landrun`** (v nixpkgs `0.1.15`). Landlock
  LSM **beží** (`/sys/kernel/security/lsm` = `capability,landlock,yama,bpf`) a
  **komponuje** s chromium namespace sandboxom (landlock pravidlá sa dedia cez
  user/pid namespaces aj exec). Preto NErozbije chromium sandbox — narozdiel od
  naivného firejail, ktorý ľudí tlačí k `--no-sandbox`.
- **Allowlist, nie denylist** — landlock je z princípu allowlist (povolíš cesty,
  zvyšok je deny). Silnejšie: nový secret v `~` je automaticky neviditeľný.
- **Fail-closed** — ak `landrun` nevie nastaviť sandbox, browser sa **nespustí**.
  Radšej žiadny browser než neuzavretý.
- **Sieť: neobmedzená** — egress je sub-projekt 3, nemiešame.
- **ws-from-ws mimo rozsah** — allowlist povolí celý profil base (všetky ws).

## 3. Návrh

### Komponent: `os-browser` zabalený do `landrun`

`os-browser <n>` (v `modules/browser.nix`) dnes spúšťa `exec chromium --user-data-dir=…`.
Po novom: `exec landrun <allowlist flagy> -- chromium --user-data-dir=…`. `landrun`
sa pridá do `runtimeInputs`.

### Allowlist (čo chromium dostane)
| Cesta | Režim | Prečo |
|---|---|---|
| `~/.local/share/os-browser` | rw | profil(y) — chromium tam píše dáta |
| `/nix/store`, `/run/current-system/sw` | ro+exec | knižnice, binárky, fonty |
| `/etc` | ro | resolv.conf, SSL certy, `/etc/fonts`, machine-id |
| `/run/user/1000` | rw | wayland socket, dbus session, pulse |
| `/tmp`, `/dev/shm` | rw | chromium IPC / shared memory |
| `/proc`, `/sys` | ro | self-introspekcia, GPU/device info |
| `/dev/dri`, `/dev/null`, `/dev/urandom` | dev | GPU, základné zariadenia |
| sieť | povolená | (egress rieši sub-projekt 3) |

### Deny (pointa — implicitné, lebo allowlist)
`~/.ssh`, `~/os`, `~/.gnupg`, zvyšok `~` okrem profilu — **neviditeľné** pre chromium
a všetky jeho child procesy (renderery dedia landlock).

### Footgun a postup
Chromium siaha na veľa ciest; **allowlist sa doladí iteráciou vo VM** (browser
nenabehne → dmesg/strace ukáže chýbajúcu cestu → pridaj → znova). Presné landrun
flagy (`--rox`, `--rw`, `--ro`, `--bind`, network) sa finalizujú v pláne podľa
`landrun --help` a reálneho správania. **Kontingencia:** ak by landlock+chromium bol
neriešiteľný, fallback je bubblewrap allowlist (`0.11.0`) — ale landrun je prvá voľba.

## 4. Súbory
- Modify: `modules/browser.nix` — `osBrowser`: pridať `landrun` do `runtimeInputs`,
  obaliť `exec` landrunom; fail-closed (žiadny fallback na neuzavretý chromium).
- Modify: `docs/hardening.md` — pridať sekciu „Browser containment".
- Bez zmeny: `os-workspace`, `os-empty-watcher` (volajú `os-browser`, ten ostáva).

## 5. Akceptačná brána + verifikácia (vo VM cez SSH)

Tri podmienky (všetky musia platiť):
1. **Sandbox neporušený** — chromium beží **bez** `--no-sandbox`, žiadne
   „No usable sandbox!"; `unshare --user --map-root-user echo ok` → `ok`.
2. **Secrety skryté** — z pohľadu browser procesu sú `~/.ssh` aj `~/os`
   **nedostupné**. Overenie: `cat /proc/<chromium-pid>/root/home/marky/.ssh/...`
   zlyhá / cesta neexistuje, prípadne probe spustený v rovnakom landlock kontexte
   nevie otvoriť `~/.ssh`.
3. **Browser funguje** — okno sa zobrazí (`swaymsg` representation = `chromium-browser`)
   a vyrenderuje stránku.

Plus: `nix eval` oboch hostov bez buildu; sway/desktopy/watcher nerozbité.

## 6. Dokumentácia (prvotriedny deliverable)
- `docs/hardening.md` — nová sekcia „Browser containment": threat model (blast radius
  v user-space), allowlist/deny tabuľka, prečo landlock (komponuje so sandboxom),
  ako overiť, fail-closed. Zvýrazniť, že `~/.ssh`/`~/os` sú skryté.
- Inline komentár v `os-browser` pri landrun obale.
- README „Hardening" — pridať vetu o browser containmente + link.

## 7. Mimo rozsahu (YAGNI / odložené)
- **Desktop-od-desktopu izolácia** (ws1 ↔ ws2 profily) — neskôr, ak vôbec.
- **Network/egress obmedzenie z browsera** — sub-projekt 3.
- Obmedzenie zariadení (kamera, USB) — neskôr.
- Dedikovaný browser user / bubblewrap — len kontingencia, ak landlock zlyhá.
