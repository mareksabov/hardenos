# Hardening

`hardenos` je **browser-centric** OS → attack surface je koncentrovaný do chromia.
Tento dokument vysvetľuje **hardening baseline**: čo robíme, **proti čomu** a **prečo
práve takto** — vrátane vecí, ktoré sme **vedome odložili** (a prečo).

> Stav: baseline (Fáza 2, sub-projekt 1) — implementované a overené vo VM.
> Spec: [`superpowers/specs/2026-06-25-hardening-baseline-design.md`](superpowers/specs/2026-06-25-hardening-baseline-design.md).
> Modul: [`../modules/hardening.nix`](../modules/hardening.nix).

## Threat model

Bránime sa primárne dvom veciam:
1. **Kompromitácia browsera (RCE).** Útočník dostane kód do chromia → chceme
   **minimálny blast radius**: nesmie escalovať z user-space do kernelu ani čítať
   pamäť/dáta iných procesov.
2. **Exfiltrácia cez sieť.** (Rieši samostatný egress kúsok; tento baseline preň
   pripravuje pôdu.)

Baseline cieli na **(1)** na úrovni kernelu a user-space povrchu.

## Vodiace pravidlo: anti-hardening výnimka

Hardening **nie je** „zapni všetko". Chromium vlastný **namespace sandbox potrebuje
unprivileged user namespaces**. Keby sme ich vypli (čo robí NixOS `hardened` profil),
chromium spadne na `--no-sandbox` — čo je **HORŠIE** než žiadne hardening. Preto
držíme:

```nix
security.allowUserNamespaces = true;
```

**Akceptačný test každej zmeny:** chromium musí bežať **so** sandboxom
(`unshare --user --map-root-user echo ok` → `ok`; v logu žiadne „No usable sandbox!").

## Controls (čo / proti čomu / prečo)

### Sysctl — pamäť a proces-izolácia
| Kľúč | Proti čomu |
|---|---|
| `kernel.yama.ptrace_scope = 1` | popnutý proces nečíta pamäť cudzích procesov cez ptrace |
| `kernel.unprivileged_bpf_disabled = 1` | zatvorí častý kernel-exploit vektor (unpriv eBPF) |
| `net.core.bpf_jit_harden = 2` | sťaží BPF JIT-spray (čitateľný len ako root — efekt vyššieho) |
| `kernel.perf_event_paranoid = 2` | žiadny unpriv perf (mainline max; `3` je downstream patch) |
| `kernel.kexec_load_disabled = 1` | popnutý root nenahradí bežiaci kernel cez kexec |
| `vm.unprivileged_userfaultfd = 0` | odoberie techniku na zľahčenie use-after-free exploitov |
| `dev.tty.ldisc_autoload = 0` | nezavádza line-discipline moduly on-demand |
| `fs.protected_{symlinks,hardlinks} = 1`, `fs.protected_{fifos,regular} = 2` | symlink/hardlink TOCTOU a zápis do cudzích súborov v sticky adresároch |
| `fs.suid_dumpable = 0` | SUID proces nevypíše core (únik pamäte) |
| `kernel.kptr_restrict = 2`, `kernel.dmesg_restrict = 1` | skryje kernel pointery a obmedzí kernel log |

### Sysctl — sieť (anti-spoof / anti-redirect)
`rp_filter = 1`, `accept_redirects = 0`, `secure_redirects = 0`, `send_redirects = 0`,
`accept_source_route = 0` (IPv4 + IPv6), `log_martians = 1`, `tcp_syncookies = 1`,
`icmp_echo_ignore_broadcasts = 1`. **Proti čomu:** IP spoofing, MITM cez ICMP
redirecty, source-routing triky, SYN-flood, broadcast amplifikácia.

### Surface reduction
| Control | Proti čomu |
|---|---|
| `boot.blacklistedKernelModules` = `dccp sctp rds tipc` (rare protokoly), `cramfs freevxfs jffs2 hfs hfsplus` (rare FS) | nepoužívaný kód v kerneli = zbytočná zraniteľnosť. **NEblacklistovať virtio** (aarch64 VM ho potrebuje). |
| `systemd.coredump.enable = false` | pád procesu (napr. chromium) nevypíše pamäť — vrátane secretov — na disk |

## Browser containment (bubblewrap)

Popnutý chromium beží ako `marky` → bez containmentu vidí `~/.ssh` (dev kľúč!),
`~/os`, dotfiles. `os-browser` preto spúšťa chromium vnútri **bubblewrap** sandboxu,
ktorý postaví obmedzený FS view: **`tmpfs` cez `$HOME`**, do ktorého sa bind-ne len
profil (`~/.local/share/os-browser`) + nutné systémové cesty. `~/.ssh`/`~/os` v tom
view **neexistujú**.

**Reálny bind-set** (overené vo VM): `--ro-bind /nix/store`, `/run/current-system`,
`/etc`, `/sys`, `/run/opengl-driver` (GL ovládače — bez nich MESA padá),
`/run/dbus` (system bus); `--proc /proc`, `--dev /dev`, `--dev-bind-try /dev/dri`
(GPU); `--tmpfs /tmp /dev/shm $HOME`; `--bind ~/.local/share/os-browser`,
`/run/user/1000` (Wayland/dbus session); `--die-with-parent --unshare-pid`.

- **Sandbox ostáva:** chromium si **vnútri** bwrapu vytvorí vlastný namespace sandbox
  (`security.allowUserNamespaces = true` z baseline to umožní). Overené: chromium
  procesy bežia v bwrap mnt-namespace (≠ host), žiadny `--no-sandbox`, žiadne
  „No usable sandbox!".
- **Fail-closed:** ak bwrap zlyhá, browser sa nespustí (žiadny unconfined chromium).
- **Overenie:** `/proc/<chromium-pid>/root/home/marky` ukáže len `.cache .config
  .local` (ephemeral tmpfs + profil) — **`.ssh` ani `os` tam nie sú**.
- **Mimo rozsah teraz:** desktop-od-desktopu (rovnaký uid vidí všetky ws profily),
  sieťové obmedzenie (egress kúsok).
- **Prečo nie landlock:** elegantnejší (on-theme), ale `landrun` sa na aarch64 VM
  nedá overiť (nie je v cache, build self-test padá). Landlock je kandidát na reálny
  x86_64 Dell. Bwrap je v cache a battle-tested na chromium (používa ho flatpak).

## Vedome odložené (a prečo)

- **Lockdown LSM** (`integrity`) — **chceli sme ho, ale nejde na stock kerneli.**
  Pri overovaní vo VM sa ukázalo, že stock NixOS kernel ho nemá skompilovaný
  (`# CONFIG_SECURITY_LOCKDOWN_LSM is not set`). Ani so správnym `security.lsm =
  [ "lockdown" ]` + `lockdown=integrity` (cmdline aj `lsm=` boli OK) sa LSM
  neaktivoval — `dmesg`: *„Unknown kernel command line parameters lockdown=integrity"*,
  `/sys/kernel/security/lockdown` nevznikol. Lockdown vyžaduje **rekompiláciu kernelu**
  (hardened/custom) → patrí k tracku reálneho Dellu, nie do stock-kernel baseline.
  *(Lekcia: kernelParam bez podpory v kerneli kernel ticho zahodí do user-space.)*
- **`security.lockKernelModules`** — silné (zákaz load modulov po boote), ale pobije
  sa s nftables (egress kúsok potrebuje nf moduly). Zapneme až po egress.
- **Plný `linuxPackages_hardened`** — na aarch64 VM by sa kompiloval (pomalé) a jeho
  defaulty vypnú userns (footgun pre chromium). Kandidát na reálny Dell — prinesie aj
  lockdown.
- **Disk encryption (LUKS), secure boot, TPM** — HW-viazané, odložené na reálny Dell.

## Ako overiť

```bash
sysctl kernel.yama.ptrace_scope            # = 1 (a ďalšie kľúče)
cat /proc/sys/kernel/kexec_load_disabled   # = 1
lsmod | grep -E 'dccp|sctp|cramfs'         # prázdne (nič blacklistnuté nie je load)
systemctl is-active systemd-coredump.socket # inactive
unshare --user --map-root-user echo ok     # ok  (chromium sandbox precondition)
```
Akceptačná brána: chromium nabehne **bez** `--no-sandbox` a bez „No usable sandbox!".

## Prevádzkové pozn.
- **Sysctl** sa aplikuje hneď pri `nixos-rebuild switch`.
- **`boot.kernelParams`** (a kernel-level zmeny vo všeobecnosti) sa aplikujú až po
  **reboote** — nie cez `switch` ani `swaymsg reload`.
