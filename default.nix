let
  # nixpkgs = fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-25.11";
  # pkgs = import <nixpkgs> { };

  pkgs = import /etc/nixos/modules/nixpkgs-master { config = {}; overlays = []; };
in
{
  laravel-reverb = pkgs.callPackage ./package.nix { };
}
