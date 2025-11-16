{ pkgs, depot, ... }:

# The package is defined in ./package.nix, but since we want to inject it into
# nixpkgs, //3p/overlays/tvl already calls it.
# Everything that requires depot needs to be addded here.
pkgs.nix_2_3.overrideAttrs (oldAttrs: {
  meta = oldAttrs.meta // {
    ci = oldAttrs.meta.ci // {
      extraSteps.export = depot.tools.releases.filteredGitPush {
        filter = ":/third_party/cppnix";
        remote = "git@github.com:tvlfyi/nix.git";
        ref = "refs/heads/2.3-maintenance";
      };
    };
  };
})
