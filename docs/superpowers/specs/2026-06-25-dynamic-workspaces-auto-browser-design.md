# Dynamické workspaces + auto-browser — Dizajn

**Dátum:** 2026-06-25
**Stav:** Schválený dizajn, pred implementačným plánom.
**Nadväzuje na:** `2026-06-24-browser-centric-nixos-design.md` (sekcia 3–4: dynamické
workspaces, browser-per-workspace). Toto je upresnenie a rozšírenie toho zámeru.

## 1. Motivácia

Fáza 1 dala statické prepínanie (`Mod+1..n`) a browser len na workspace 1 pri štarte.
Cieľ tu: **macOS-spaces UX** — desktopy vznikajú na požiadanie, a keďže je to
browser-centrický OS, **nový desktop rovno dostane vlastnú inštanciu browsera**.

## 2. Rozhodnutia (potvrdené s userom)

- **Navigačný model:** nekonečné dynamické desktopy, GNOME-style. `Cmd+Shift+Right`
  na poslednom desktope vytvorí nový (sekvenčne 1→2→3…). `Cmd+Shift+Left` ide doľava,
  na desktope 1 sa zastaví (žiadny wrap). Prázdne desktopy po odchode zanikajú
  (natívne sway správanie).
- **Auto-browser scope:** browser sa spustí **len pri vzniku NOVÉHO desktopu**
  (šípka za posledný, alebo skok na číslo čo ešte neexistuje). Návrat na desktop,
  kde si browser zavrel, ho **NEznovuotvára** — ostane prázdny a po odchode zanikne.
  Zachováva „destroys when empty".
- **Štruktúra modulov:** všetky workspace-navigačné bindings sa presunú zo
  `sway.nix` do `browser.nix`, lebo navigácia je tu neoddeliteľná od
  browser-per-workspace. `sway.nix` ostane čisté WM jadro.
- **RAM:** každý desktop = jedna chromium inštancia (hlavná cena na 4 GB).
  **Zámerne bez umelého limitu** (YAGNI) — používateľ kontroluje počtom otvorených
  desktopov.

## 3. Komponenty

### `os-workspace` (nový helper, v `browser.nix`)

`pkgs.writeShellApplication`, `runtimeInputs = [ sway jq ]`. Argument:
`next` | `prev` | `<číslo>`.

Logika:
```
current = swaymsg -t get_workspaces | jq -r '.[] | select(.focused).num'
target  = next  -> current + 1
          prev  -> max(1, current - 1)
          <N>   -> N
existed = swaymsg -t get_workspaces | jq "any(.num == $target)"
swaymsg workspace number $target          # vytvorí ak neexistuje, prepne fokus
if existed == false:  os-browser $target  # auto-browser len pri vzniku
```

Jeden helper obsluhuje šípky, čísla aj gestá → jednotné správanie a jediné miesto
s logikou auto-browsera.

### `browser.nix` — vlastní navigáciu

`config.d` z `browser.nix` definuje všetky workspace bindings (viď tabuľka nižšie),
ďalej ponecháva manuálne `Cmd+Return` (os-browser na aktuálnom ws) a autostart
`exec os-browser 1`.

### `sway.nix` — slim

Odstránia sa workspace bindings + gestá (pôvodné riadky ~13–22). Ostáva: `$mod`,
`$mod+Shift+q` (kill), `$mod+Shift+e` (exit), `default_border none`,
`hide_edge_borders both`, greetd, sessionVariables, include `config.d/*`.

## 4. Finálne klávesy

| Klávesa | Akcia |
|---|---|
| `Cmd+Shift+Right` | `os-workspace next` — nový desktop + browser ak za posledným |
| `Cmd+Shift+Left` | `os-workspace prev` — doľava, na 1 stop |
| `Cmd+1..4` | `os-workspace 1..4` — skok; ak číslo nové → vytvor + browser |
| `Cmd+Return` | `os-browser` na aktuálnom ws (manuálne znovuotvorenie) |
| `Cmd+T` | `foot` (bez zmeny) |
| `Cmd+Shift+Q` | zabi okno — takto sa zatvára terminál aj browser |
| 3-prstové gesto ←/→ | `os-workspace next` / `prev` |

## 5. Správanie end-to-end

1. Boot → desktop 1 + browser (profil `ws1`).
2. `Cmd+Shift+Right` na poslednom → vznikne desktop 2 → browser (profil `ws2`).
3. `Cmd+Shift+Left` → späť na 1, žiadny nový browser (desktop 2 ostáva s browserom).
4. Na desktope 2 `Cmd+Shift+Q` → browser zavretý → desktop 2 prázdny.
5. Odchod z prázdneho desktopu 2 → sway ho zruší.
6. Profily per číslo (`~/.local/share/os-browser/ws$N`) prežijú zánik/obnovu —
   znovu vytvorený desktop 2 dostane ten istý profil.

## 6. Mimo rozsahu (YAGNI)

- Limit počtu desktopov / browserov.
- Re-spawn browsera pri návrate na vyprázdnený desktop.
- Vlastný „terminálový" workspace mimo aktuálneho `Cmd+T` správania.

## 7. Overenie (vo VM)

Build + pozorovateľné správanie (žiadne unit testy, viď CLAUDE.md):
1. `nix eval` oboch hostov (vm, laptop) prejde bez buildu (architektúrna nezávislosť).
2. `nixos-rebuild switch --flake ~/os#vm` prejde.
3. Manuálne vo VM: Cmd+Shift+Right vytvorí desktop + browser; Cmd+Shift+Left
   zastaví na 1; Cmd+1..4 skáče/vytvára; zavretie browsera + odchod zruší desktop;
   Cmd+Shift+Q zatvorí foot.
