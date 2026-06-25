{ config, pkgs, lib, ... }:
let
  # StevenBlack hosts (hosts-format blocklist), pinnutý na konkrétny tag kvôli
  # reprodukovateľnosti. Aktualizácia: zmeň tag v url a doplň nový hash cez
  # `nix store prefetch-file <url>` vo VM.
  stevenblack = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/StevenBlack/hosts/3.14.139/hosts";
    hash = "sha256-JvFY0lv+XCTOsSK3bJi3bEQGdbFEYdCUaH23KVXSMjU=";
  };
  # Filtruj len 0.0.0.0 riadky v ČISTOM Nixe (žiadny IFD/derivácia).
  # Dôvod: IFD (readFile na runCommand) by si vynútil build derivácie pre cieľovú
  # architektúru -> evaluácia x86_64 laptop hosta na aarch64 VM by chcela buildovať
  # x86_64 grep a padla by. fetchurl je fixed-output (rovnaký store path na oboch
  # archoch, už realizovaný), takže readFile naň je architektúrne nezávislé.
  blocklist = lib.concatStringsSep "\n"
    (builtins.filter (l: lib.hasPrefix "0.0.0.0 " l)
      (lib.splitString "\n" (builtins.readFile stevenblack)));
in
{
  # Vlož blocklist do /etc/hosts deklaratívne.
  # Platí systémovo -> pre všetky inštancie browsera naraz.
  networking.extraHosts = blocklist;
}
