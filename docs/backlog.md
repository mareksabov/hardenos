# Dokumentačný backlog

`hardenos` je open-source + learning projekt → **kvalitná dokumentácia je súčasť
„hotovo"**, nie afterthought. Každá funkcia má mať čitateľské *čo / prečo / proti
čomu / ako overiť*, nielen kód a krátku zmienku v README.

Tento súbor sleduje **dlh** — veci, ktoré sú hotové v kóde, ale ešte nemajú plnú
dokumentáciu, plus konvenciu pre nové veci.

## Konvencia (od 2026-06-25)
Ku každej zmene **paralelne** vznikne dokumentácia. Pri hotovej funkcii skontroluj:
- rationale (prečo táto voľba, aké alternatívy, trade-offy),
- pri bezpečnosti: proti akému threatu chráni,
- ako sa overí, že funguje,
- README/CLAUDE.md/specs v súlade s realitou.

## Dlh — dorobiť dokumentáciu (hotové v kóde, docs neúplné)

- [ ] **Dynamické desktopy (macOS-spaces UX)** — `os-workspace` (next/prev/N, nový
  desktop = nový browser), commity `8895dbb`/`af50322`. Spec+plán existujú
  (`specs/2026-06-25-dynamic-workspaces-auto-browser-design.md`), ale chýba
  čitateľská user/architektúra stránka (ako to funguje, prečo keybinding-based a nie
  daemon, profily per číslo).
- [ ] **Auto-close prázdneho desktopu** — `os-empty-watcher`, commit `3ae346a`.
  Zdokumentovať mechanizmus (IPC subscribe, prečo `exec` raz pri štarte a zomrie
  s odhlásením, edge „posledný desktop").
- [ ] **`$mod` = Alt/Option (nie Cmd/Control)** — commity `7ee2ea9`→`6720fa2`.
  Rationale je v README/CLAUDE komentári, ale patrí do súvislej „klávesy a prečo
  práve takto na Macu/UTM" stránky (macOS preberá Cmd; Control by zatienil app Ctrl
  skratky; Alt je kompromis).
- [ ] **Adblock, waybar auto-hide, display fix** (Fáza 1) — overiť, či majú
  dostatočnú rationale dokumentáciu, prípadne doplniť do jednotnej štruktúry.

## Otvorená otázka štruktúry docs
Zvážiť `docs/` rozloženie pre open-source čitateľa: napr. `docs/hardening.md`
(z baseline kúsku), `docs/desktops.md`, `docs/keybindings.md`, `docs/architecture.md`
— namiesto všetkého len v README. Vyriešiť pri prvom hardening kúsku.
