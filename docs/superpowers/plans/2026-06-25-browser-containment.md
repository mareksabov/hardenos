# Browser containment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wrap chromium in a bubblewrap sandbox so a compromised browser cannot read `~/.ssh`, `~/os`, or other home secrets — without breaking chromium's own sandbox.

**Architecture:** `os-browser` (in `modules/browser.nix`) execs `bwrap` with a restricted FS view (tmpfs over `$HOME`, bind only the profile dir + system paths) which then execs chromium. The exact bind-set is tuned empirically on the VM until the three acceptance gates pass.

**Tech Stack:** NixOS 25.11, `bubblewrap 0.11.0`, ungoogled-chromium, sway/Wayland.

## Global Constraints

- **Acceptance gate (all three):** (1) chromium runs WITH its sandbox — no `--no-sandbox`, no "No usable sandbox!"; (2) `~/.ssh` and `~/os` are inaccessible from inside the bwrap view; (3) the browser actually renders.
- **Fail-closed:** if `bwrap` can't set up the sandbox, the browser does NOT fall back to an unconfined chromium.
- **Network unrestricted** — NO `--unshare-net` (egress is sub-project 3).
- **ws-from-ws out of scope** — bind the whole profile base `~/.local/share/os-browser`.
- **No IFD; pure Nix; both hosts must `nix eval` without building.**
- **Empirical loop is controller-driven on the VM** — macOS has no nix; the bind-set is discovered by edit→push→deploy→launch→observe→refine. VM: `ssh hardenos-vm` (marky), root `ssh -i ~/.ssh/hardenos_vm -o IdentitiesOnly=yes root@192.168.64.8`, repo `/home/marky/os`, sway socket `/run/user/1000/sway-ipc.*.sock`, `WAYLAND_DISPLAY=wayland-1`.
- **Sandbox stays intact is the hard invariant** — `security.allowUserNamespaces = true` (from baseline) lets chromium nest its userns inside bwrap's.

---

### Task 1: Wrap `os-browser` in bubblewrap (VM-iterative)

**Files:**
- Modify: `modules/browser.nix` — `osBrowser`: add `pkgs.bubblewrap` to `runtimeInputs`, wrap the `exec chromium` in `exec bwrap … -- chromium …`.

**Interfaces:**
- Consumes: nothing new (chromium, bubblewrap from nixpkgs).
- Produces: `os-browser <n>` still launches a per-ws chromium, now bwrap-confined. `os-workspace`/`os-empty-watcher` keep calling `os-browser` unchanged.

- [ ] **Step 1: Replace the `osBrowser` `text` body in `modules/browser.nix`** with the candidate bwrap wrapper

```nix
  osBrowser = pkgs.writeShellApplication {
    name = "os-browser";
    runtimeInputs = [ pkgs.ungoogled-chromium pkgs.bubblewrap ];
    text = ''
      ws="''${1:-1}"
      base="$HOME/.local/share/os-browser"
      profile="$base/ws''${ws}"
      mkdir -p "$profile"
      # bubblewrap: tmpfs cez $HOME → ~/.ssh, ~/os a dotfiles ZMIZNÚ z view;
      # bind-ne sa len profil + nutné systémové cesty. chromium si VNÚTRI vytvorí
      # vlastný namespace sandbox (potrebuje allowUserNamespaces=true z baseline).
      # fail-closed: ak bwrap zlyhá, exec zlyhá a browser sa nespustí (žiadny
      # unconfined fallback).
      exec bwrap \
        --ro-bind /nix/store /nix/store \
        --ro-bind /run/current-system /run/current-system \
        --ro-bind /etc /etc \
        --ro-bind /sys /sys \
        --proc /proc \
        --dev /dev \
        --dev-bind-try /dev/dri /dev/dri \
        --tmpfs /tmp \
        --tmpfs /dev/shm \
        --tmpfs "$HOME" \
        --bind "$base" "$base" \
        --bind /run/user/1000 /run/user/1000 \
        --die-with-parent \
        --unshare-pid \
        chromium \
          --user-data-dir="$profile" \
          --ozone-platform=wayland \
          --start-maximized \
          --no-first-run \
          --no-default-browser-check
    '';
  };
```

- [ ] **Step 2: Hand-verify Nix (no nix on Mac)** — `''${1:-1}`, `''${ws}` correctly escaped; bwrap line-continuations valid; `runtimeInputs` has both `ungoogled-chromium` and `bubblewrap`; rest of `browser.nix` (osWorkspace, osEmptyWatcher, config.d) untouched.

- [ ] **Step 3: Commit (candidate)**
```bash
git add modules/browser.nix
git commit -m "feat(browser): confine chromium in bubblewrap (hide home secrets)"
```

- [ ] **Step 4: Deploy to VM (controller)**
```bash
git push origin main
ssh hardenos-vm 'cd ~/os && git fetch -q && git reset --hard origin/main && nix eval .#nixosConfigurations.vm.config.system.build.toplevel.drvPath >/dev/null && nix eval .#nixosConfigurations.laptop.config.system.build.toplevel.drvPath >/dev/null && echo eval-both-ok'
ssh -i ~/.ssh/hardenos_vm -o IdentitiesOnly=yes root@192.168.64.8 'nixos-rebuild switch --flake /home/marky/os#vm 2>&1 | tail -1'
```
Expected: both eval without building; switch "Done."

- [ ] **Step 5: GATE 1+3 — launch under bwrap, confirm it renders with sandbox**
```bash
ssh hardenos-vm 'bash -lc "export SWAYSOCK=\$(ls /run/user/1000/sway-ipc.*.sock|head -1); swaymsg exec os-browser\ 9; sleep 8; swaymsg -t get_workspaces | grep -A2 \"\\\"num\\\": 9\" | grep -c chromium-browser"'
# diagnose failures: run os-browser directly and read stderr for missing paths / sandbox errors
ssh hardenos-vm 'bash -lc "export WAYLAND_DISPLAY=wayland-1 XDG_RUNTIME_DIR=/run/user/1000; timeout 8 os-browser 9 2>&1 | grep -iE \"sandbox|bwrap|no such file|cannot|denied\" | head -20; true"'
```
Expected: ws9 shows `chromium-browser` (window mapped). The stderr probe shows NO "No usable sandbox!" and NO fatal "bwrap: ... No such file". If chromium fails, the stderr names the missing bind → add it to the wrapper and repeat Steps 1–5. **Iterate until the window maps and no sandbox error appears.**

- [ ] **Step 6: GATE 2 — secrets are hidden inside the bwrap view**
```bash
# same bwrap binds, but run `ls` instead of chromium — must NOT see ~/.ssh or ~/os
ssh hardenos-vm 'bash -lc "
  base=\$HOME/.local/share/os-browser
  bwrap --ro-bind /nix/store /nix/store --ro-bind /etc /etc --proc /proc --dev /dev \
        --tmpfs /tmp --tmpfs \$HOME --bind \$base \$base \
        -- /bin/sh -c \"ls -a \$HOME; echo ---; ls \$HOME/.ssh 2>&1; ls \$HOME/os 2>&1\"
"'
```
Expected: home listing shows only `.local` (the bound profile path), NOT `.ssh`/`os`; `ls ~/.ssh` and `ls ~/os` print "No such file or directory". (Confirms the containment goal.)

- [ ] **Step 7: GATE — nothing else broke + cleanup**
```bash
ssh hardenos-vm 'bash -lc "export SWAYSOCK=\$(ls /run/user/1000/sway-ipc.*.sock|head -1); swaymsg \"[workspace=9] kill\"; swaymsg workspace number 1; swaymsg -t get_workspaces | grep -c num; pgrep -af bin/os-empty-watcher >/dev/null && echo watcher-ok"'
```
Expected: sway responds, watcher running. (Manual on screen: Alt+Shift+→ creates desktop + confined browser.)

- [ ] **Step 8: If the bind-set changed during iteration, commit the final wrapper**
```bash
git add modules/browser.nix
git commit -m "fix(browser): finalize bubblewrap bind-set (verified on VM)"
git push origin main
```

---

### Task 2: Documentation

**Files:**
- Modify: `docs/hardening.md` — add "Browser containment" section.
- Modify: `README.md` — one line under "Hardening".

**Interfaces:**
- Consumes: the final bind-set from Task 1 (document the actual binds, not the candidate if they differ).

- [ ] **Step 1: Add "Browser containment" section to `docs/hardening.md`** (after the controls, before "Vedome odložené")

```markdown
## Browser containment (bubblewrap)

Popnutý chromium beží ako `marky` → bez containmentu vidí `~/.ssh`, `~/os`, dotfiles.
`os-browser` preto spúšťa chromium vnútri **bubblewrap** sandboxu, ktorý postaví
obmedzený FS view: `tmpfs` cez `$HOME`, bind len profil (`~/.local/share/os-browser`)
+ nutné systémové cesty (`/nix/store`, `/etc`, `/run/user/1000` pre Wayland, `/dev`,
`/proc`, `/sys`). `~/.ssh` a `~/os` v tom view **neexistujú**.

- **Sandbox ostáva:** chromium si vnútri vytvorí vlastný namespace sandbox
  (`security.allowUserNamespaces = true` z baseline to umožní). Overené: žiadny
  `--no-sandbox`, žiadne „No usable sandbox!".
- **Fail-closed:** ak bwrap zlyhá, browser sa nespustí (žiadny unconfined chromium).
- **Mimo rozsah teraz:** desktop-od-desktopu izolácia (rovnaký uid vidí všetky profily),
  sieťové obmedzenie (egress kúsok).
- **Prečo nie landlock:** elegantnejší (on-theme), ale `landrun` sa na aarch64 VM
  nedá overiť (nebuilduje sa). Landlock je kandidát na reálny x86_64 Dell.

Overenie: `bwrap … -- ls ~/.ssh` → „No such file or directory"; chromium nabehne a
vyrenderuje stránku.
```

- [ ] **Step 2: Update the "Hardening" section in `README.md`** — add to the bullet list (after the surface-reduction bullet)

```markdown
- **Browser containment** — chromium beží v `bubblewrap` sandboxe (tmpfs `~`, bind len
  profil + systém) → popnutý browser nevidí `~/.ssh`, `~/os`, dotfiles. Sandbox chromia
  ostáva funkčný. Detail: `docs/hardening.md`.
```

- [ ] **Step 3: Commit**
```bash
git add docs/hardening.md README.md
git commit -m "docs: document browser containment (bubblewrap)"
git push origin main
```

- [ ] **Step 4: Verify docs match code** — the binds listed in `docs/hardening.md` match the final `os-browser` wrapper in `modules/browser.nix`.

---

## Poznámky k overeniu
- Žiadne unit testy — overenie = `nix eval` + pozorovateľné správanie vo VM cez SSH.
- **Žiadny reboot netreba** (žiadne kernelParams) — `switch` stačí.
- Spec: `docs/superpowers/specs/2026-06-25-browser-containment-design.md`.
- Ak bwrap+chromium nested sandbox nepôjde rozumne dotiahnuť: prehodnotiť (landlock na Delli / systemd-run). „Však sa hráme."
