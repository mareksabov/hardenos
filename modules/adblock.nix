{ config, pkgs, lib, ... }:
let
  # StevenBlack hosts (hosts-format blocklist), pinnutý na konkrétny tag kvôli
  # reprodukovateľnosti. Aktualizácia: zmeň tag v url a doplň nový hash cez
  # `nix store prefetch-file <url>` vo VM.
  stevenblack = pkgs.fetchurl {
    url = "https://raw.githubusercontent.com/StevenBlack/hosts/3.14.139/hosts";
    hash = "sha256-JvFY0lv+XCTOsSK3bJi3bEQGdbFEYdCUaH23KVXSMjU=";
  };
in
{
  # Extrahuj len 0.0.0.0 riadky a vlož ich do /etc/hosts deklaratívne.
  # Platí systémovo -> pre všetky inštancie browsera naraz.
  networking.extraHosts = builtins.readFile (pkgs.runCommand "blocklist-hosts" { } ''
    grep '^0\.0\.0\.0 ' ${stevenblack} > $out || true
  '');
}
