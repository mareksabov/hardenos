# Hardening baseline — Dizajn (Fáza 2, sub-projekt 1)

**Dátum:** 2026-06-25
**Stav:** Schválený dizajn, pred implementačným plánom.
**Kontext:** Prvý kúsok hardening roadmapy (Fáza 2). Roadmapa a threat model vznikli
v brainstorme 2026-06-25. Ďalšie kúsky: (2) browser containment, (3) egress kontrola.
Odložené na reálny Dell: LUKS disk encryption, secure boot + TPM.

## 1. Prečo (threat model — anchor)

User vybral dva primárne threaty:

1. **Kompromitácia browsera (RCE).** Chromium je koncentrovaný attack surface
   (browser-only OS attack surface neodstraňuje, ale ho koncentruje — viď pôvodný
   dizajn, sekcia 2). Keď útočník dostane kód do browsera, chceme **minimálny blast
   radius**: nesmie escalovať z user-space do kernelu a nesmie čítať pamäť/dáta iných
   procesov.
2. **Exfiltrácia cez sieť.** (Rieši sub-projekt 3; baseline preň pripravuje pôdu.)

Tento baseline cieli na **(1) — sťažiť RCE → kernel-escape a cross-process únik** na
úrovni kernelu a user-space povrchu. Robí to **bez** rozbitia chromium vlastného
sandboxu.

### Vodiace pravidlo (učebné jadro)

Hardening **nie je** „zapni všetko". Je to „zmenši povrch a stvrď izoláciu —
**okrem** toho, čo rozbije tvoj legitímny sandbox, a vedz prečo". Najdôležitejší
riadok celého kúsku je preto zámerná **anti-hardening výnimka**:

```nix
# Chromium namespace sandbox POTREBUJE unprivileged user namespaces.
# NixOS stock kernel ich má zapnuté by default; KĽÚČOVÉ je ich NEvypnúť (čo robí
# hardened profil / security.allowUserNamespaces=false) — inak chromium spadne na
# --no-sandbox, čo je HORŠIE než žiadne hardening. Držíme to explicitne zapnuté:
security.allowUserNamespaces = true;
```

> **Pozn. k zápisu:** `kernel.unprivileged_userns_clone` je Debian/Ubuntu downstream
> sysctl — na mainline NixOS kerneli NEEXISTUJE. Správny NixOS výraz je
> `security.allowUserNamespaces` (default `true`); nastavíme ho explicitne ako
> deklaratívnu poistku zámeru.

## 2. Rozhodnutia (potvrdené s userom)

- **Stock kernel + cielené hardening**, nie `linuxPackages_hardened`. Dôvod: na
  aarch64 dev-VM by sa hardened kernel kompiloval (pomalé na 4 GB), jeho defaulty
  vypnú userns (footgun pre chromium). Stock kernel ostáva v cache → rýchly dev-loop.
  Plný hardened kernel je kandidát až na reálny Dell.
- **Browser-aware:** každý control prejde akceptačnou bránou „chromium beží so
  sandboxom".
- **Lockdown LSM — ODLOŽENÉ** (pôvodne `integrity`). Pri VM verifikácii sa zistilo,
  že stock NixOS kernel lockdown LSM nemá skompilovaný (`CONFIG_SECURITY_LOCKDOWN_LSM
  is not set`) → nedá sa aktivovať bez rekompilácie kernelu. Patrí k hardened-kernel /
  reálny Dell tracku. Viz §3.C a §7.
- **`security.lockKernelModules` ODLOŽENÉ** v rámci tohto kúsku — zapne sa až po
  sub-projekte 3 (egress), lebo nftables potrebuje načítať nf moduly; lock by sa
  s tým pobil bez preloadu. Odložené vedome, nie zabudnuté.

## 3. Controls

Všetky browser-safe. Pri každom: **čo / proti čomu / pozn.**

### A. Sysctl — pamäť a proces-izolácia
| Kľúč | Hodnota | Proti čomu |
|---|---|---|
| `security.allowUserNamespaces` *(nie sysctl)* | `true` | **zachovanie** chromium sandboxu (výnimka, nie hardening) |
| `kernel.yama.ptrace_scope` | `1` | popnutý proces nečíta pamäť cudzích procesov cez ptrace |
| `kernel.unprivileged_bpf_disabled` | `1` | zatvorí častý kernel-exploit vektor (unpriv eBPF) |
| `net.core.bpf_jit_harden` | `2` | sťaží JIT-spray útoky na BPF |
| `kernel.perf_event_paranoid` | `2` | zamedzí unpriv perf (mainline max; `3` je downstream patch) |
| `kernel.kexec_load_disabled` | `1` | žiadny load nového kernelu za behu |
| `vm.unprivileged_userfaultfd` | `0` | odoberie techniku na zľahčenie use-after-free exploitov |
| `dev.tty.ldisc_autoload` | `0` | nezavádza line-discipline moduly na požiadanie |
| `fs.protected_symlinks` / `protected_hardlinks` | `1` | klasické symlink/hardlink TOCTOU útoky |
| `fs.protected_fifos` / `protected_regular` | `2` | zápis do cudzích fifo/súborov v sticky adresároch |
| `fs.suid_dumpable` | `0` | SUID proces nevypíše core (únik pamäte) |
| `kernel.kptr_restrict` | `2` | *(už je)* skryje kernel pointery z `/proc` |
| `kernel.dmesg_restrict` | `1` | *(už je)* obmedzí čítanie kernel logu |

### B. Sysctl — sieť (anti-spoof / anti-redirect)
`accept_redirects=0`, `secure_redirects=0`, `send_redirects=0`,
`accept_source_route=0` (IPv4 `all`+`default`, relevantné aj IPv6),
`log_martians=1`, `tcp_syncookies=1`, `icmp_echo_ignore_broadcasts=1`,
`rp_filter=1` *(už je)*. **Proti čomu:** MITM cez ICMP redirecty, IP spoofing,
source-routing triky, SYN-flood.

### C. Kernel image
- Kexec zhodíme cez sysctl `kernel.kexec_load_disabled = 1` (skupina A). **Proti
  čomu:** popnutý root nenahradí bežiaci kernel cez kexec.

> **Lockdown LSM — ODLOŽENÉ (zistené pri VM verifikácii).** Pôvodne sme chceli
> `lockdown=integrity`. Stock NixOS kernel ho ale **nemá skompilovaný**
> (`# CONFIG_SECURITY_LOCKDOWN_LSM is not set`), takže sa nedá aktivovať bez
> rekompilácie kernelu — ani cez `security.lsm = [ "lockdown" ]` + `lockdown=integrity`
> (cmdline aj `lsm=` boli správne, ale kód LSM v kerneli chýba: `dmesg` „Unknown
> kernel command line parameters", `/sys/kernel/security/lockdown` nevznikol).
> Lockdown preto patrí k **hardened-kernel / reálny Dell** tracku, nie do
> stock-kernel baseline. (Aj `security.protectKernelImage` je mimo — vynútila by
> `lockdown=confidentiality` a rovnako potrebuje lockdown v kerneli.)

### D. Surface reduction
- `boot.blacklistedKernelModules = [ "dccp" "sctp" "rds" "tipc" "cramfs"
  "freevxfs" "jffs2" "hfs" "hfsplus" ]` — zriedkavé sieťové protokoly a súborové
  systémy, ktoré tento OS nepoužíva. **Proti čomu:** každý zavedený modul = kód
  v kerneli = potenciálna zraniteľnosť. **Pozn.:** NEblacklistovať virtio (aarch64
  VM ho potrebuje) ani nič, čo chce sway/chromium.
- `systemd.coredump.enable = false` — **proti čomu:** pád procesu (napr. chromium)
  nevypíše pamäť — vrátane secretov — na disk.

## 4. Súbory
- Modify: `modules/hardening.nix` — sysctl skupiny A+B, sekcia C (kexec cez sysctl;
  lockdown odložený), D (blacklist modulov, coredump off). Zachovať existujúce
  (doas, firewall, gc).
- Create: `docs/hardening.md` — čitateľská rationale dokumentácia (viď §6).
- Bez zmeny: hosty.

## 5. Verifikácia (vo VM, cez SSH — žiadne unit testy)

1. **Arch-nezávislosť:** `nix eval` vm aj laptop bez buildu (čistý Nix, žiadny IFD).
2. **Aplikácia:** sysctl + coredump sa aplikujú pri `switch`; blacklist modulov sa
   prejaví po reboote (ak by boli načítané — tu nie sú). Lockdown (kernelParam) je
   odložený, takže baseline **reboot nevyžaduje** (reboot bol potrebný len na
   dôkaz, že stock kernel lockdown nepodporuje).
3. **Controls aktívne:**
   - `sysctl <key>` = očakávaná hodnota (každý kľúč z A+B; `bpf_jit_harden` čitateľný
     len ako root — efekt `unprivileged_bpf_disabled=1`).
   - `cat /proc/sys/kernel/kexec_load_disabled` → `1`.
   - `lsmod` neukáže blacklistnuté moduly; `systemd-coredump.socket` je inactive.
4. **AKCEPTAČNÁ BRÁNA — chromium sandbox neporušený:**
   - `os-browser` nabehne **bez** `--no-sandbox` a bez „No usable sandbox!".
   - `chrome://sandbox` / `chrome://gpu` ukáže aktívny namespace sandbox; existujú
     zygote procesy.
   - `unshare --user --map-root-user echo ok` → `ok` (userns stále dostupné).
5. **Nič sa nerozbilo:** sway beží; dynamické desktopy + auto-browser + watcher
   fungujú (rýchly re-test).

## 6. Dokumentácia (prvotriedny deliverable)

`hardenos` je open-source + learning projekt → dokumentácia je súčasť „hotovo",
nie afterthought.
- **`docs/hardening.md`** (nový): čitateľská stránka — threat model, a pre **každý
  control** tabuľka *čo / proti čomu / prečo táto voľba / ako overiť*. Vrátane
  zvýraznenia **anti-hardening výnimky** (userns) ako učebného bodu.
- **Inline komentáre** v `modules/hardening.nix` — pri každom netriviálnom kľúči
  jednovetné „proti čomu", nech je modul samovysvetľujúci.
- **README** — krátka sekcia „Hardening" odkazujúca na `docs/hardening.md`.
- **CLAUDE.md** — pridať gotchu „kernelParams (lockdown/protectKernelImage) chcú
  reboot, nie switch/reload".

## 7. Mimo rozsahu (YAGNI / odložené)
- **Lockdown LSM** (`integrity`/`confidentiality`) — stock kernel ho nemá
  skompilovaný (`CONFIG_SECURITY_LOCKDOWN_LSM` not set); vyžaduje hardened/custom
  kernel → tracku reálneho Dellu.
- `security.lockKernelModules` (až po egress sub-projekte).
- Plný `linuxPackages_hardened` (kandidát na reálny Dell — prinesie aj lockdown).
- AppArmor/SELinux MAC (samostatný budúci kúsok, ak vôbec).
- Disk encryption, secure boot, TPM (HW-viazané, odložené na Dell).
