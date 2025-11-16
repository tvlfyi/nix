{ stdenv
, path # pkgs.path
, nixDependencies
, lib
, autoreconfHook
, perl
, callPackage
, pkg-config
, autoconf-archive
, bison
, flex
, jq
, libxslt
, libxml2
, docbook_xsl_ns
, docbook5
, libcpuid
, libseccomp
, util-linuxMinimal
, boost
, brotli
, bzip2
, curl
, editline
, libsodium
, openssl
, sqlite
, xz
, gtest
, libarchive
, busybox-sandbox-shell

  # cross incorrect references fix
, bash
, coreutils
, gzip
, gnutar

, storeDir ? "/nix/store"
, stateDir ? "/nix/var"
, confDir ? "/etc"

  # RISC-V support in progress https://github.com/seccomp/libseccomp/pull/50
, withLibseccomp ? lib.meta.availableOn stdenv.hostPlatform libseccomp
, enableStatic ? stdenv.hostPlatform.isStatic
, enableDocumentation ? stdenv.buildPlatform.canExecute stdenv.hostPlatform
}:

let
  inherit (nixDependencies) boehmgc;

  version = "2.3.18-canon";
  src = lib.cleanSource ./.;

  self = stdenv.mkDerivation {
    pname = "nix";

    inherit version src;

    outputs = [
      "out"
      "dev"
    ]
    ++ lib.optionals enableDocumentation [
      "man"
      "doc"
    ];

    # TODO(sterni): move check into autoconf
    env.CXXFLAGS = lib.optionalString stdenv.hostPlatform.isDarwin " -fexperimental-library";

    hardeningEnable = lib.optionals (!stdenv.hostPlatform.isDarwin) [ "pie" ];
    hardeningDisable = [
      "shadowstack"
    ]
    ++ lib.optional stdenv.hostPlatform.isMusl "fortify";

    nativeBuildInputs = [
      pkg-config
      autoconf-archive
      autoreconfHook
      bison
      flex
      jq
    ]
    ++ lib.optionals enableDocumentation [
      libxslt
      libxml2
      docbook_xsl_ns
      docbook5
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      util-linuxMinimal
    ];

    buildInputs = [
      boost
      brotli
      bzip2
      curl
      editline
      libsodium
      openssl
      sqlite
      xz
      gtest
      libarchive
    ]
    ++ lib.optionals (stdenv.hostPlatform.isx86_64) [
      libcpuid
    ]
    ++ lib.optionals withLibseccomp [
      libseccomp
    ];

    propagatedBuildInputs = [
      boehmgc
    ];

    postPatch = ''
      patchShebangs --build tests
    '';

    preConfigure =
      # Copy libboost_context so we don't get all of Boost in our closure.
      # https://github.com/NixOS/nixpkgs/issues/45462
      lib.optionalString (!stdenv.hostPlatform.isStatic) ''
        mkdir -p $out/lib
        cp -pd ${boost}/lib/{libboost_context*,libboost_thread*,libboost_system*} $out/lib
        rm -f $out/lib/*.a
        ${lib.optionalString stdenv.hostPlatform.isLinux ''
          chmod u+w $out/lib/*.so.*
          patchelf --set-rpath $out/lib:${lib.getLib stdenv.cc.cc}/lib $out/lib/libboost_thread.so.*
        ''}
      ''
      +
      # TODO(sterni): backport?
      # On all versions before c9f51e87057652db0013289a95deffba495b35e7, which
      # removes config.nix entirely and is not present in 2.3.x, we need to
      # patch around an issue where the Nix configure step pulls in the build
      # system's bash and other utilities when cross-compiling.
      lib.optionalString (stdenv.buildPlatform != stdenv.hostPlatform) ''
        mkdir tmp/
        substitute corepkgs/config.nix.in tmp/config.nix.in \
          --subst-var-by bash ${bash}/bin/bash \
          --subst-var-by coreutils ${coreutils}/bin \
          --subst-var-by bzip2 ${bzip2}/bin/bzip2 \
          --subst-var-by gzip ${gzip}/bin/gzip \
          --subst-var-by xz ${xz}/bin/xz \
          --subst-var-by tar ${gnutar}/bin/tar \
          --subst-var-by tr ${coreutils}/bin/tr
        mv tmp/config.nix.in corepkgs/config.nix.in
      '';

    configureFlags = [
      "--with-store-dir=${storeDir}"
      "--localstatedir=${stateDir}"
      "--sysconfdir=${confDir}"
      "--enable-gc"
    ]
    ++ lib.optionals (!enableDocumentation) [
      "--disable-doc-gen"
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [
      "--with-sandbox-shell=${busybox-sandbox-shell}/bin/busybox"
    ]
    ++ lib.optionals
      (
        stdenv.hostPlatform != stdenv.buildPlatform
          && stdenv.hostPlatform ? nix
          && stdenv.hostPlatform.nix ? system
      )
      [
        "--with-system=${stdenv.hostPlatform.nix.system}"
      ]
    ++ lib.optionals (!withLibseccomp) [
      "--disable-seccomp-sandboxing"
    ];

    makeFlags = [
      # gcc runs multi-threaded LTO using make and does not yet detect the new fifo:/path style
      # of make jobserver. until gcc adds support for this we have to instruct make to use this
      # old style or LTO builds will run their linking on only one thread, which takes forever.
      "--jobserver-style=pipe"
      "profiledir=$(out)/etc/profile.d"
    ]
    ++ lib.optional (stdenv.hostPlatform != stdenv.buildPlatform) "PRECOMPILE_HEADERS=0"
    ++ lib.optional (stdenv.hostPlatform.isDarwin) "PRECOMPILE_HEADERS=1";

    installFlags = [ "sysconfdir=$(out)/etc" ];

    doInstallCheck = true;

    # socket path becomes too long otherwise
    preInstallCheck =
      lib.optionalString stdenv.hostPlatform.isDarwin ''
        export TMPDIR=$NIX_BUILD_TOP
      ''
      # Prevent crashes in libcurl due to invoking Objective-C `+initialize` methods after `fork`.
      # See http://sealiesoftware.com/blog/archive/2017/6/5/Objective-C_and_fork_in_macOS_1013.html.
      + lib.optionalString stdenv.hostPlatform.isDarwin ''
        export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
      ''
      + ''
        # nixStatic otherwise does not find its man pages in tests.
        export MANPATH=$man/share/man:$MANPATH
      '';

    separateDebugInfo = stdenv.hostPlatform.isLinux;

    enableParallelBuilding = true;

    # https://github.com/NixOS/nix/issues/10222
    # spurious test/add.sh failures
    enableParallelChecking = false;

    passthru = {
      inherit boehmgc;
      aws-sdk-cpp = null;

      perl-bindings = perl.pkgs.toPerlModule (
        callPackage (/* pkgs. */ path + "/pkgs/tools/package-management/nix/nix-perl.nix") {
          nix = self;
        }
      );

      # Build instructions:
      #   mg shell :shell
      #   ./bootstrap.sh
      #   configurePhase
      #   buildPhase
      #   installPhase
      #   ./inst/bin/nix-instantiate --version
      #
      # You may also want to run:
      #   export PKG_CONFIG_PATH=$prefix/lib/pkgconfig:$PKG_CONFIG_PATH
      #   export PATH=$prefix/bin:$PATH
      shell = self.overrideAttrs (_: {
        outputs = [ "out" ];
        separateDebugInfo = false;
        dontAddPrefix = true;
        preConfigure = "";
        configureFlags = [
          "--with-store-dir=${storeDir}"
          "--localstatedir=${stateDir}"
          "--sysconfdir=${confDir}"
        ];
        makeFlags = [ ];

        shellHook = ''
          export prefix=${toString ./.}/inst
          installFlags="sysconfdir=$prefix/etc"
          configureFlags+=" --prefix=$prefix"
        '';
      });
    };

    meta = {
      ci.targets = [ "perl-bindings" ];
      description = "Powerful package manager that makes package management reliable and reproducible (TVL fork)";
      homepage = "https://github.com/tvlfyi/nix";
      license = lib.licenses.lgpl21Plus;
      platforms = lib.platforms.unix;
      outputsToInstall = [ "out" ] ++ lib.optionals enableDocumentation [ "man" ];
      mainProgram = "nix";

      knownVulnerabilities = [
        "CVE-2024-38531"
        "CVE-2024-47174"
        "CVE-2025-46415"
        "CVE-2025-46416"
        "CVE-2025-52991"
        "CVE-2025-52992"
        "CVE-2025-52993"
      ];
    };
  };
in
self
