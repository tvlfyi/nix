{ stdenv
, lib
, perl
, pkg-config
, curl
, nix
, libsodium
, boost
, autoreconfHook
, autoconf-archive
, xz
, meson
, ninja
, bzip2
, libarchive
,
}:

let
  mkConfigureOption = autoconfOption: value:
    lib.withFeatureAs true autoconfOption value;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "nix-perl";
  inherit (nix) version src;

  postUnpack = "sourceRoot=$sourceRoot/perl";

  buildInputs = [
    boost
    bzip2
    curl
    libsodium
    nix
    perl
    xz
  ];

  # Not cross-safe since Nix checks for curl/perl via
  # NEED_PROG/find_program, but both seem to be needed at runtime
  # as well.
  nativeBuildInputs = [
    pkg-config
    perl
    curl

    autoconf-archive
    autoreconfHook
  ];

  # `perlPackages.Test2Harness` is marked broken for Darwin
  doCheck = !stdenv.hostPlatform.isDarwin;

  nativeCheckInputs = [
    perl.pkgs.Test2Harness
  ];

  configureFlags = [
    (mkConfigureOption "dbi" "${perl.pkgs.DBI}/${perl.libPrefix}")
    (mkConfigureOption "dbd-sqlite" "${perl.pkgs.DBDSQLite}/${perl.libPrefix}")
  ];

  preConfigure = "export NIX_STATE_DIR=$TMPDIR";

  passthru = { inherit perl; };
})
