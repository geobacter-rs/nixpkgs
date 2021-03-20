{ lib, stdenv, removeReferencesTo, pkgsBuildBuild, pkgsBuildHost, pkgsBuildTarget
, llvmShared, llvmSharedForBuild, llvmSharedForHost, llvmSharedForTarget
, fetchFromGitHub, file, python3
, darwin, cmake, geobacterRust, rustPlatform
, pkg-config, openssl, ninja
, which, libffi
, withBundledLLVM ? false
, enableRustcDev ? true
, version
, sha256
, rev
, vendorSha256
, patches ? []
}:

let
  inherit (lib) optionals optional optionalString concatStringsSep;
  inherit (darwin.apple_sdk.frameworks) Security;
in stdenv.mkDerivation rec {
  pname = "geobacter-rustc";
  inherit version;

  src = fetchFromGitHub {
    owner = "geobacter-rs";
    repo = "rust";
    fetchSubmodules = true;
    inherit rev sha256;
  };
  cargoDeps = rustPlatform.fetchCargoTarball {
    inherit src;
    name = "${pname}-${version}";
    sha256 = vendorSha256;
  };

  postUnpack = ''
    (mkdir source/vendor && cd source/vendor && tar xf "${cargoDeps}" --strip-components=1);
  '';

  __darwinAllowLocalNetworking = true;

  # rustc complains about modified source files otherwise
  dontUpdateAutotoolsGnuConfigScripts = true;

  # Running the default `strip -S` command on Darwin corrupts the
  # .rlib files in "lib/".
  #
  # See https://github.com/NixOS/nixpkgs/pull/34227
  #
  # Running `strip -S` when cross compiling can harm the cross rlibs.
  # See: https://github.com/NixOS/nixpkgs/pull/56540#issuecomment-471624656
  stripDebugList = [ "bin" ];

  NIX_LDFLAGS = toString (
       # when linking stage1 libstd: cc: undefined reference to `__cxa_begin_catch'
       optional (stdenv.isLinux && !withBundledLLVM) "--push-state --as-needed -lstdc++ --pop-state"
    ++ optional (stdenv.isDarwin && !withBundledLLVM) "-lc++"
    ++ optional stdenv.isDarwin "-rpath ${llvmSharedForHost}/lib");

  RUSTFLAGS_NOT_BOOTSTRAP = "-Z always-encode-mir -Z always-emit-metadata";
  # Increase codegen units to introduce parallelism within the compiler.
  RUSTFLAGS = "-Ccodegen-units=10";
  RUSTC_VERBOSE = 2;

  # We need rust to build rust. If we don't provide it, configure will try to download it.
  # Reference: https://github.com/rust-lang/rust/blob/master/src/bootstrap/configure.py
  configureFlags = let
    setBuild  = "--set=target.${geobacterRust.toRustTarget stdenv.buildPlatform}";
    setHost   = "--set=target.${geobacterRust.toRustTarget stdenv.hostPlatform}";
    setTarget = "--set=target.${geobacterRust.toRustTarget stdenv.targetPlatform}";
    ccForBuild  = "${pkgsBuildBuild.targetPackages.stdenv.cc}/bin/${pkgsBuildBuild.targetPackages.stdenv.cc.targetPrefix}cc";
    cxxForBuild = "${pkgsBuildBuild.targetPackages.stdenv.cc}/bin/${pkgsBuildBuild.targetPackages.stdenv.cc.targetPrefix}c++";
    ccForHost  = "${pkgsBuildHost.targetPackages.stdenv.cc}/bin/${pkgsBuildHost.targetPackages.stdenv.cc.targetPrefix}cc";
    cxxForHost = "${pkgsBuildHost.targetPackages.stdenv.cc}/bin/${pkgsBuildHost.targetPackages.stdenv.cc.targetPrefix}c++";
    ccForTarget  = "${pkgsBuildTarget.targetPackages.stdenv.cc}/bin/${pkgsBuildTarget.targetPackages.stdenv.cc.targetPrefix}cc";
    cxxForTarget = "${pkgsBuildTarget.targetPackages.stdenv.cc}/bin/${pkgsBuildTarget.targetPackages.stdenv.cc.targetPrefix}c++";
  in [
    "--release-channel=nightly"
    "--enable-parallel-compiler"
    "--enable-llvm-assertions"
    "--enable-optimize-llvm"
    "--enable-full-bootstrap"
    "--disable-ninja"
    "--set=build.rustc=${rustPlatform.rust.rustc}/bin/rustc"
    "--set=build.cargo=${rustPlatform.rust.cargo}/bin/cargo"
    # Is rustfmt really needed??
    "--set=build.rustfmt=${rustPlatform.rust.rustfmt}/bin/rustfmt"
    "--enable-rpath"
    "--enable-vendor"
    "--build=${geobacterRust.toRustTargetSpec stdenv.buildPlatform}"
    "--host=${geobacterRust.toRustTargetSpec stdenv.hostPlatform}"
    # std is built for all platforms in --target. When building a cross-compiler
    # we need to add the host platform as well so rustc can compile build.rs
    # scripts.
    "--target=${concatStringsSep "," ([
      (geobacterRust.toRustTargetSpec stdenv.targetPlatform)
    ] ++ optionals (stdenv.hostPlatform != stdenv.targetPlatform) [
      (geobacterRust.toRustTargetSpec stdenv.hostPlatform)
    ])}"

    "${setBuild}.cc=${ccForBuild}"
    "${setHost}.cc=${ccForHost}"
    "${setTarget}.cc=${ccForTarget}"

    "${setBuild}.linker=${ccForBuild}"
    "${setHost}.linker=${ccForHost}"
    "${setTarget}.linker=${ccForTarget}"

    "${setBuild}.cxx=${cxxForBuild}"
    "${setHost}.cxx=${cxxForHost}"
    "${setTarget}.cxx=${cxxForTarget}"
  ] ++ optionals (!withBundledLLVM) [
    "--enable-llvm-link-shared"
    "${setBuild}.llvm-config=${llvmSharedForBuild}/bin/llvm-config"
    "${setHost}.llvm-config=${llvmSharedForHost}/bin/llvm-config"
    "${setTarget}.llvm-config=${llvmSharedForTarget}/bin/llvm-config"
  ] ++ optionals (stdenv.isLinux && !stdenv.targetPlatform.isRedox) [
    "--enable-profiler" # build libprofiler_builtins
  ] ++ optionals stdenv.buildPlatform.isMusl [
    "${setBuild}.musl-root=${pkgsBuildBuild.targetPackages.stdenv.cc.libc}"
  ] ++ optionals stdenv.hostPlatform.isMusl [
    "${setHost}.musl-root=${pkgsBuildHost.targetPackages.stdenv.cc.libc}"
  ] ++ optionals stdenv.targetPlatform.isMusl [
    "${setTarget}.musl-root=${pkgsBuildTarget.targetPackages.stdenv.cc.libc}"
  ];

  # The bootstrap.py will generated a Makefile that then executes the build.
  # The BOOTSTRAP_ARGS used by this Makefile must include all flags to pass
  # to the bootstrap builder.
  postConfigure = ''
    substituteInPlace Makefile \
      --replace 'BOOTSTRAP_ARGS :=' 'BOOTSTRAP_ARGS := --jobs $(NIX_BUILD_CORES)'
  '';

  # the rust build system complains that nix alters the checksums
  dontFixLibtool = true;

  inherit patches;

  postPatch = ''
    patchShebangs src/etc configure

    ${optionalString (!withBundledLLVM) "rm -rf src/llvm-project"}

    # Fix the configure script to not require curl as we won't use it
    sed -i configure \
      -e '/probe_need CFG_CURL curl/d'

    # Useful debugging parameter
    export VERBOSE=2;
    export RUSTFLAGS_NOT_BOOTSTRAP="-Z always-encode-mir -Z always-emit-metadata";
    # Increase codegen units to introduce parallelism within the compiler.
    export RUSTFLAGS="-Ccodegen-units=10";
    export RUSTC_VERBOSE=2;
  '';

  #buildPhase = ''
  #  python ./x.py --stage 2 dist --config config.toml
  #'';

  # rustc unfortunately needs cmake to compile llvm-rt but doesn't
  # use it for the normal build. This disables cmake in Nix.
  dontUseCmakeConfigure = true;

  dontUseNinjaBuild = true;

  nativeBuildInputs = [
    file python3 rustPlatform.rust.rustc cmake
    which libffi removeReferencesTo pkg-config
  ];

  buildInputs = [ openssl ]
    ++ optional stdenv.isDarwin Security
    ++ optional (!withBundledLLVM) llvmShared;

  outputs = [ "out" "man" "doc" ];
  setOutputFlags = false;

  postInstall = lib.optionalString enableRustcDev ''
    # install rustc-dev components. Necessary to build rls, clippy...
    python x.py dist rustc-dev
    tar xf build/dist/rustc-dev*tar.gz
    cp -r rustc-dev*/rustc-dev*/lib/* $out/lib/
    rm $out/lib/rustlib/install.log
    for m in $out/lib/rustlib/manifest-rust*
    do
      sort --output=$m < $m
    done

  '' + ''
    # remove references to llvm-config in lib/rustlib/x86_64-unknown-linux-gnu/codegen-backends/librustc_codegen_llvm-llvm.so
    # and thus a transitive dependency on ncurses
    find $out/lib -name "*.so" -type f -exec remove-references-to -t ${llvmShared} '{}' '+'
  '';

  configurePlatforms = [];

  # https://github.com/NixOS/nixpkgs/pull/21742#issuecomment-272305764
  # https://github.com/rust-lang/rust/issues/30181
  # enableParallelBuilding = false;

  setupHooks = ./setup-hook.sh;

  requiredSystemFeatures = [ "big-parallel" ];

  passthru.llvm = llvmShared;

  meta = with lib; {
    homepage = "https://github.com/geobacter-rs/geobacter";
    description = "A Rust fork with support for programming co-processors, like GPUs";
    maintainers = with maintainers; [ DiamondLovesYou ];
    license = [ licenses.mit licenses.asl20 ];
    platforms = platforms.linux ++ platforms.darwin;
  };
}
