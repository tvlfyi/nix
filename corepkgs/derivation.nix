/* This is the implementation of the ‘derivation’ builtin function.
   It's actually a wrapper around the ‘derivationStrict’ primop. */

# take all the drv attributes, but default outputs to `["out"]` if unset
drvAttrs @ { outputs ? [ "out" ], ... }:

let

  # apply drvStrict to _all_ the attrs (so we're dealing with a single drv here)
  strict = derivationStrict drvAttrs;

  # merge the drvAttrs (passed in!) with the outputsList, with a final
  # `all` attribute that contains the value of everything from
  # outputsList
  #
  # also merge in drvAttrs itself
  commonAttrs = drvAttrs // (builtins.listToAttrs outputsList) //
    { all = map (x: x.value) outputsList;
      inherit drvAttrs;
    };

    # for each given output, return a nv-pair for the output and the
    # value being the common attrs (which again contain the output
    # itself!), the outpath of the output, the drvpath of the wwhole
    # derivation, and so on.
    #
    # curious - `type = derivation` is not set earlier??
  outputToAttrListElement = outputName:
    { name = outputName;
      value = commonAttrs // {
        outPath = builtins.getAttr outputName strict;
        drvPath = strict.drvPath;
        type = "derivation";
        inherit outputName;
      };
    };

  outputsList = map outputToAttrListElement outputs;

in (builtins.head outputsList).value
