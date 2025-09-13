{ pkgs, ... }:

# The package is defined in ./package.nix, but since we want to inject it into
# nixpkgs, //3p/overlays/tvl already calls it.
pkgs.nix_2_3
