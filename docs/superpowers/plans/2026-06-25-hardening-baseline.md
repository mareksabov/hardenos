# Hardening baseline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Browser-aware kernel/userspace hardening baseline that shrinks the RCE→kernel-escape and cross-process attack surface without breaking chromium's sandbox.

**Architecture:** Extend `modules/hardening.nix` with sysctl groups (process/memory + network), lockdown LSM, and surface reduction — all stock-kernel, no IFD. Keep unprivileged user namespaces ON (`security.allowUserNamespaces = true`) so chromium's namespace sandbox keeps working. Document every control's rationale.

**Tech Stack:** NixOS 25.11 (stock kernel), `boot.kernel.sysctl`, `boot.kernelParams`, lockdown LSM, Yama LSM.

## Global Constraints

- **Browser-safe is the acceptance gate:** after every change, chromium MUST still run WITH its sandbox (no `--no-sandbox`, no "No usable sandbox!"). `unshare --user --map-root-user echo ok` MUST print `ok`.
- **Stock kernel only** — no `linuxPackages_hardened` (would compile on aarch64, breaks dev-loop, disables userns).
- **No IFD** — pure Nix; both hosts (`vm` aarch64, `laptop` x86_64) must `nix eval` without building.
- **macOS has NO nix** — implementer edits + commits on Mac; all `nix eval` / `switch` / `reboot` / runtime checks run on the VM via SSH (controller). VM: `ssh hardenos-vm` (marky), root `ssh -i ~/.ssh/hardenos_vm -o IdentitiesOnly=yes root@192.168.64.8`, repo `/home/marky/os`.
- **GIT loop:** edit→commit (Mac)→push→VM `git fetch && git reset --hard origin/main`→`nixos-rebuild switch`.
- **kernelParams need REBOOT** — `lockdown=` is NOT applied by `switch` or `swaymsg reload`; only a real reboot. (sysctl IS applied by `switch`.)
- **Docs are a first-class deliverable** (open-source + learning project): inline rationale comments in code tasks + a reader-facing `docs/hardening.md`.
- Keep existing `hardening.nix` content (doas, firewall default-deny, gc, existing sysctl).

---

### Task 1: Sysctl hardening (process/memory + network) + keep userns

**Files:**
- Modify: `modules/hardening.nix` — replace the `boot.kernel.sysctl` block, add `security.allowUserNamespaces = true`.

**Interfaces:**
- Produces: hardened sysctl state; `security.allowUserNamespaces = true` guard consumed conceptually by chromium sandbox.

- [ ] **Step 1: Add the userns guard + expand sysctl in `modules/hardening.nix`**

Replace the existing block:
```nix
  # Sysctl hardening
  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "net.ipv4.conf.all.rp_filter" = 1;
    "net.ipv4.conf.default.rp_filter" = 1;
  };
```
with:
```nix
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
```

- [ ] **Step 2: Hand-verify Nix (no nix on Mac)** — všetky kľúče sú `"string" = int;`, blok je validný attrset, `security.allowUserNamespaces` je mimo `boot.kernel.sysctl`. Žiadne `${}` (žiadne escaping). Existujúci `doas`/`firewall`/`gc` netknuté.

- [ ] **Step 3: Commit**
```bash
git add modules/hardening.nix
git commit -m "feat(hardening): sysctl process/memory + network hardening, keep userns"
```

- [ ] **Step 4: VM verify (controller, via SSH) — eval + switch (sysctl netreba reboot)**
```bash
# push + sync
git push origin main
ssh hardenos-vm 'cd ~/os && git fetch -q && git reset --hard origin/main'
# arch-independence: oba hosty evaluujú bez buildu
ssh hardenos-vm 'cd ~/os && nix eval .#nixosConfigurations.vm.config.system.build.toplevel.drvPath && nix eval .#nixosConfigurations.laptop.config.system.build.toplevel.drvPath'
# switch
ssh -i ~/.ssh/hardenos_vm -o IdentitiesOnly=yes root@192.168.64.8 'nixos-rebuild switch --flake /home/marky/os#vm'
```
Expected: oba eval vypíšu `...-nixos-system-*.drv` bez "building"; switch skončí "Done."

- [ ] **Step 5: VM verify — sysctl aktívne + AKCEPTAČNÁ BRÁNA (sandbox)**
```bash
ssh hardenos-vm 'for k in kernel.yama.ptrace_scope kernel.unprivileged_bpf_disabled net.core.bpf_jit_harden kernel.perf_event_paranoid kernel.kexec_load_disabled fs.protected_regular net.ipv4.conf.all.accept_redirects net.ipv4.tcp_syncookies; do sysctl -n $k | sed "s/^/$k = /"; done'
# userns stále funguje (chromium sandbox precondition)
ssh hardenos-vm 'unshare --user --map-root-user echo ok'
# browser stále beží so sandboxom (spustí ho sway s WAYLAND prostredím)
ssh hardenos-vm 'export SWAYSOCK=$(ls /run/user/1000/sway-ipc.*.sock | head -1); swaymsg exec os-browser\ 9; sleep 5; swaymsg -t get_workspaces | grep -A2 "\"num\": 9" | grep representation'
```
Expected: ptrace_scope=1, unprivileged_bpf_disabled=1, bpf_jit_harden=2, perf_event_paranoid=2, kexec_load_disabled=1, protected_regular=2, accept_redirects=0, tcp_syncookies=1; `unshare` → `ok`; ws9 representation obsahuje `chromium-browser` (browser nabehol = sandbox OK). Cleanup: `ssh hardenos-vm 'export SWAYSOCK=$(ls /run/user/1000/sway-ipc.*.sock|head -1); swaymsg "[workspace=9] kill"; swaymsg workspace number 1'`.

---

### Task 2: Lockdown LSM + surface reduction (reboot-gated)

**Files:**
- Modify: `modules/hardening.nix` — add `boot.kernelParams`, `boot.blacklistedKernelModules`, `systemd.coredump.enable = false`.

**Interfaces:**
- Consumes: Task 1's `kernel.kexec_load_disabled` (kexec already off; this task adds lockdown + module/coredump surface).

- [ ] **Step 1: Add lockdown + surface reduction in `modules/hardening.nix`**

After the `boot.kernel.sysctl` block, add:
```nix
  # Lockdown LSM (integrity): blokuje modifikáciu bežiaceho kernelu (/dev/mem,
  # nepodpísané moduly, …). POZOR: kernelParam → aplikuje sa až po REBOOTE.
  # NEpoužívame security.protectKernelImage (tá vynúti lockdown=confidentiality).
  boot.kernelParams = [ "lockdown=integrity" ];

  # Surface reduction: zriedkavé protokoly/FS, ktoré OS nepoužíva = menej kódu
  # v kerneli = menší attack surface. (NEblacklistovať virtio — aarch64 VM ho chce.)
  boot.blacklistedKernelModules = [
    "dccp" "sctp" "rds" "tipc"                   # zriedkavé sieťové protokoly
    "cramfs" "freevxfs" "jffs2" "hfs" "hfsplus"  # zriedkavé súborové systémy
  ];

  # Pád procesu (napr. chromium) nevypíše pamäť — vrátane secretov — na disk.
  systemd.coredump.enable = false;
```

- [ ] **Step 2: Hand-verify Nix** — `boot.kernelParams` je list stringov, `boot.blacklistedKernelModules` list stringov, `systemd.coredump.enable` bool. Žiadne `${}`. Neduplikuje kľúče z Tasku 1.

- [ ] **Step 3: Commit**
```bash
git add modules/hardening.nix
git commit -m "feat(hardening): lockdown=integrity LSM + module/coredump surface reduction"
```

- [ ] **Step 4: VM verify — eval + switch + REBOOT (kernelParams!)**
```bash
git push origin main
ssh hardenos-vm 'cd ~/os && git fetch -q && git reset --hard origin/main && nix eval .#nixosConfigurations.vm.config.system.build.toplevel.drvPath && nix eval .#nixosConfigurations.laptop.config.system.build.toplevel.drvPath'
ssh -i ~/.ssh/hardenos_vm -o IdentitiesOnly=yes root@192.168.64.8 'nixos-rebuild boot --flake /home/marky/os#vm && systemctl reboot'
# počkaj ~40s na reštart, potom over reachability
sleep 40; until ssh -o ConnectTimeout=5 hardenos-vm 'true' 2>/dev/null; do sleep 5; done; echo up
```
Expected: oba eval bez buildu; `nixos-rebuild boot` (nie switch — lockdown chce čistý boot) prejde; VM sa vráti online.

- [ ] **Step 5: VM verify — lockdown aktívny + moduly + AKCEPTAČNÁ BRÁNA**
```bash
ssh hardenos-vm 'cat /sys/kernel/security/lockdown'                 # → ...[integrity]...
ssh hardenos-vm 'cat /proc/sys/kernel/kexec_load_disabled'          # → 1
ssh hardenos-vm 'lsmod | grep -E "^(dccp|sctp|rds|tipc|cramfs|freevxfs|jffs2|hfs|hfsplus)\b" || echo "no blacklisted modules loaded"'
ssh hardenos-vm 'systemctl is-active systemd-coredump.socket || echo coredump-off'
# sandbox gate po reboote
ssh hardenos-vm 'unshare --user --map-root-user echo ok'
ssh hardenos-vm 'export SWAYSOCK=$(ls /run/user/1000/sway-ipc.*.sock|head -1); swaymsg exec os-browser\ 9; sleep 5; swaymsg -t get_workspaces | grep -A2 "\"num\": 9" | grep representation'
```
Expected: lockdown shows `[integrity]`; kexec_load_disabled=1; no blacklisted modules; coredump off; `unshare` → `ok`; ws9 has `chromium-browser` (sandbox intact post-lockdown). Cleanup ws9 as in Task 1.

- [ ] **Step 6: VM verify — nič sa nerozbilo**
```bash
ssh hardenos-vm 'export SWAYSOCK=$(ls /run/user/1000/sway-ipc.*.sock|head -1); swaymsg -t get_workspaces | grep -c "\"num\""'
ssh hardenos-vm 'pgrep -af "bin/os-empty-watcher" >/dev/null && echo watcher-ok || echo watcher-MISSING'
```
Expected: sway responds; watcher running (started by sway at boot via its `exec`). Manuálne (na obrazovke): Alt+Shift+→ vytvorí desktop + browser.

---

### Task 3: Documentation (first-class deliverable)

**Files:**
- Create: `docs/hardening.md` — reader-facing rationale.
- Modify: `README.md` — short "Hardening" section linking to it.
- Modify: `CLAUDE.md` — add reboot gotcha for kernelParams.
- Modify: `docs/backlog.md` — none of today's debt is cleared here; leave as-is (hardening is newly documented, not backfilled).

**Interfaces:**
- Consumes: the controls implemented in Tasks 1–2 (must match exactly).

- [ ] **Step 1: Create `docs/hardening.md`**

```markdown
# Hardening

`hardenos` je browser-centric OS → attack surface je koncentrovaný do chromia.
Tento baseline **sťažuje útočníkovi únik z popnutého browsera** (RCE → kernel-escape,
cross-process únik) na úrovni kernelu a user-space povrchu — **bez** rozbitia
chromium vlastného sandboxu.

## Threat model
Popnutý chromium (RCE) má mať minimálny blast radius: nesmie escalovať do kernelu
ani čítať pamäť/dáta iných procesov. (Sieťovú exfiltráciu rieši samostatný egress
kúsok.)

## Vodiace pravidlo: anti-hardening výnimka
Hardening nie je „zapni všetko". Chromium namespace sandbox **potrebuje**
unprivileged user namespaces; keby sme ich vypli (čo robí NixOS hardened profil),
chromium spadne na `--no-sandbox` = HORŠIE. Preto držíme `security.allowUserNamespaces
= true`. Akceptačný test každej zmeny: chromium beží SO sandboxom.

## Controls (čo / proti čomu / prečo)
| Control | Proti čomu | Pozn. |
|---|---|---|
| `security.allowUserNamespaces = true` | — (výnimka) | chromium sandbox to potrebuje |
| `kernel.yama.ptrace_scope = 1` | čítanie pamäte cudzích procesov | |
| `kernel.unprivileged_bpf_disabled = 1` + `net.core.bpf_jit_harden = 2` | eBPF/JIT exploit vektory | |
| `kernel.perf_event_paranoid = 2` | unpriv perf info-leak | `3` je downstream patch |
| `kernel.kexec_load_disabled = 1` | výmena bežiaceho kernelu | |
| `vm.unprivileged_userfaultfd = 0`, `dev.tty.ldisc_autoload = 0` | UAF/ldisc techniky | |
| `fs.protected_{symlinks,hardlinks,fifos,regular}`, `fs.suid_dumpable = 0` | TOCTOU, únik core | |
| sieť: `accept_redirects/source_route = 0`, `send_redirects = 0`, `rp_filter = 1`, `log_martians`, `tcp_syncookies`, `icmp_echo_ignore_broadcasts` | spoofing, MITM redirect, SYN-flood | |
| `boot.kernelParams = ["lockdown=integrity"]` | modifikácia bežiaceho kernelu | **chce reboot**; nie `confidentiality` (rozbije debug) |
| `boot.blacklistedKernelModules` (dccp/sctp/rds/tipc, cramfs/…) | nepoužívaný kód v kerneli | NEblacklistovať virtio |
| `systemd.coredump.enable = false` | secrety z pamäte na disk | |

## Vedome odložené
- `security.lockKernelModules` — až po egress kúsku (nftables chce nf moduly).
- `linuxPackages_hardened` — kandidát na reálny Dell.
- LUKS encryption, secure boot, TPM — HW-viazané (reálny Dell).

## Ako overiť
`sysctl <key>`; `cat /sys/kernel/security/lockdown` → `[integrity]`;
`unshare --user --map-root-user echo ok` → `ok`; chromium nabehne bez
„No usable sandbox!". **kernelParams (lockdown) sa aplikujú až po reboote.**
```

- [ ] **Step 2: Add "Hardening" section to `README.md`** (za sekciu Funkcie)

```markdown
## Hardening

Browser-centric OS → attack surface koncentrovaný v chromiu. Baseline (stock kernel,
browser-safe) sťažuje únik z popnutého browsera: sysctl (ptrace/bpf/perf/fs/sieť),
`lockdown=integrity` LSM, blacklist nepoužívaných modulov, bez coredumpov. Chromium
sandbox ostáva funkčný (`security.allowUserNamespaces = true`). Detaily a rationale:
[`docs/hardening.md`](docs/hardening.md).
```

- [ ] **Step 3: Add reboot gotcha to `CLAUDE.md`** (do sekcie „Vývojový loop", za riadok o `swaymsg reload`)

```markdown
- **`boot.kernelParams` (napr. `lockdown=`) sa aplikujú až po REBOOTE** — nie cez
  `nixos-rebuild switch` ani `swaymsg reload`. Použi `nixos-rebuild boot` + reboot.
  (Sysctl sa naopak aplikuje hneď pri `switch`.)
```

- [ ] **Step 4: Commit**
```bash
git add docs/hardening.md README.md CLAUDE.md
git commit -m "docs: hardening baseline rationale (docs/hardening.md, README, CLAUDE gotcha)"
```

- [ ] **Step 5: Verify docs accuracy** — porovnaj `docs/hardening.md` tabuľku s reálnym `modules/hardening.nix` (každý control v docs existuje v kóde a naopak). README link `docs/hardening.md` je platná cesta.

---

## Poznámky k overeniu
- Žiadne unit testy — overenie = `nix eval` (arch-nezávislosť) + pozorovateľný stav vo VM cez SSH.
- **Reboot len v Task 2** (lockdown kernelParam). Task 1 (sysctl) a Task 3 (docs) reboot nepotrebujú.
- Spec: `docs/superpowers/specs/2026-06-25-hardening-baseline-design.md`.
