{ lib, stdenv
, fetchFromGitHub
, cmake, ninja
, python3
, libffi
, libbfd
, libpfm
, libxml2
, ncurses
, version
, release_version
, zlib
, git
, buildPackages
, buildType ? "Release"
, enableAssertions ? false
, enableManpages ? false
, enableSharedLibraries ? true
, enablePFM ? !(stdenv.isDarwin
  || stdenv.isAarch64 # broken for Ampere eMAG 8180 (c2.large.arm on Packet) #56245
  || stdenv.isAarch32 # broken for the armv7l builder
)
, enablePolly ? false
}:

let
  inherit (lib) optional optionals optionalString;

  # Used when creating a version-suffixed symlink of libLLVM.dylib
  shortVersion = with lib;
    concatStringsSep "." (take 1 (splitString "." release_version));

  cmakeSuffix = lib.strings.toLower buildType;

in stdenv.mkDerivation (rec {
  pname = "geobacter-llvm";
  inherit version;

  src = fetchFromGitHub {
    owner = "geobacter-rs";
    repo = "llvm-project";
    rev = "d71a532c6eb3513b5eace11fef55e09489821e40";
    fetchSubmodules = true;
    sha256 = "1p2p22fz2168diiv037979585yxqs9flkvb1f5vr1fn7ff5cj688";
    leaveDotGit = true;
    deepClone = false;
  };
  polly_src = "${src}/polly";

  dontUseCmakeBuildDir = true;
  dontStrip = (buildType == "Debug" || buildType == "RelWithDebInfo");

  outputs = [ "out" "python" ]
    ++ optional enableSharedLibraries "lib";

  nativeBuildInputs = [ cmake python3 ninja git ]
    ++ optionals enableManpages [ python3.pkgs.sphinx python3.pkgs.recommonmark ];

  buildInputs = [ libxml2 libffi ]
    ++ optional enablePFM libpfm; # exegesis

  propagatedBuildInputs = [ ncurses zlib ];
  patches = [
    ./0001-Prevent-cmake-from-making-lib-cmake-llvm-read-only.patch
  ];
  postPatch = optionalString stdenv.isDarwin ''
    substituteInPlace llvm/cmake/modules/AddLLVM.cmake \
      --replace 'set(_install_name_dir INSTALL_NAME_DIR "@rpath")' "set(_install_name_dir)" \
      --replace 'set(_install_rpath "@loader_path/../lib''${LLVM_LIBDIR_SUFFIX}" ''${extra_libdir})' ""
  ''
  # Patch llvm-config to return correct library path based on --link-{shared,static}.
  + optionalString (enableSharedLibraries) ''
    substitute '${./llvm-outputs.patch}' ./llvm-outputs.patch --subst-var lib
    patch -p1 < ./llvm-outputs.patch
  '' + ''
    # FileSystem permissions tests fail with various special bits
    substituteInPlace llvm/unittests/Support/CMakeLists.txt \
      --replace "Path.cpp" ""
    rm llvm/unittests/Support/Path.cpp
  '' + optionalString stdenv.hostPlatform.isMusl ''
    patch -p1 -i ${../TLI-musl.patch}
    substituteInPlace llvm/unittests/Support/CMakeLists.txt \
      --replace "add_subdirectory(DynamicLibrary)" ""
    rm llvm/unittests/Support/DynamicLibrary/DynamicLibraryTest.cpp
    # valgrind unhappy with musl or glibc, but fails w/musl only
    rm llvm/test/CodeGen/AArch64/wineh4.mir
  '' + optionalString stdenv.hostPlatform.isAarch32 ''
    # skip failing X86 test cases on 32-bit ARM
    rm llvm/test/DebugInfo/X86/convert-debugloc.ll
    rm llvm/test/DebugInfo/X86/convert-inlined.ll
    rm llvm/test/DebugInfo/X86/convert-linked.ll
    rm llvm/test/tools/dsymutil/X86/op-convert.test
  '' + optionalString (stdenv.hostPlatform.system == "armv6l-linux") ''
    # Seems to require certain floating point hardware (NEON?)
    rm llvm/test/ExecutionEngine/frem.ll
  '' + ''
    patchShebangs llvm/test/BugPoint/compile-custom.ll.py
  '';

  preConfigure = ''
    mkdir -p ../build;
  '';

  # hacky fix: created binaries need to be run before installation
  preBuild = ''
    mkdir -p $out/
    ln -sv $PWD/lib $out
  '';

  # E.g. mesa.drivers use the build-id as a cache key (see #93946):
  LDFLAGS = optionalString (enableSharedLibraries && !stdenv.isDarwin) "-Wl,--build-id=sha1";

  cmakeDir = "llvm";
  cmakeFlags = with stdenv; [
    "-B" "../build"
    "-DCMAKE_BUILD_TYPE=${buildType}"
    "-DLLVM_INSTALL_UTILS=ON"  # Needed by rustc
    "-DLLVM_BUILD_TESTS=OFF"
    "-DLLVM_ENABLE_FFI=ON"
    "-DLLVM_ENABLE_RTTI=OFF"
    "-DLLVM_HOST_TRIPLE=${stdenv.hostPlatform.config}"
    "-DLLVM_DEFAULT_TARGET_TRIPLE=${stdenv.hostPlatform.config}"
    "-DLLVM_ENABLE_DUMP=ON"
    "-DLLVM_PARALLEL_LINK_JOBS=4"
    "-DLLVM_ENABLE_ASSERTIONS=${if enableAssertions then "ON" else  "OFF" }"
  ] ++ optionals enableSharedLibraries [
    "-DLLVM_LINK_LLVM_DYLIB=ON"
  ] ++ optionals enablePolly [
    "-DLLVM_ENABLE_PROJECTS=polly"
  ] ++ optionals enableManpages [
    "-DLLVM_BUILD_DOCS=ON"
    "-DLLVM_ENABLE_SPHINX=ON"
    "-DSPHINX_OUTPUT_MAN=ON"
    "-DSPHINX_OUTPUT_HTML=OFF"
    "-DSPHINX_WARNINGS_AS_ERRORS=OFF"
  ] ++ optionals (!isDarwin) [
    "-DLLVM_BINUTILS_INCDIR=${libbfd.dev}/include"
  ] ++ optionals isDarwin [
    "-DLLVM_ENABLE_LIBCXX=ON"
    "-DCAN_TARGET_i386=false"
  ] ++ optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
    "-DCMAKE_CROSSCOMPILING=True"
    "-DLLVM_TABLEGEN=${buildPackages.geobacterLlvm_latest}/bin/llvm-tblgen"
  ];

  ninjaFlags = "-C ../build";

  postBuild = ''
    rm -fR $out
  '';

  preCheck = ''
    export LD_LIBRARY_PATH=$LD_LIBRARY_PATH''${LD_LIBRARY_PATH:+:}$PWD/lib
  '';

  postInstall = ''
    mkdir -p $python/share
    mv $out/share/opt-viewer $python/share/opt-viewer
  ''
  + optionalString enableSharedLibraries ''
    moveToOutput "lib/libLLVM-*" "$lib"
    moveToOutput "lib/libLLVM${stdenv.hostPlatform.extensions.sharedLibrary}" "$lib"
  ''
  + optionalString (enableSharedLibraries && (!stdenv.isDarwin)) ''
    substituteInPlace "$out/lib/cmake/llvm/LLVMExports-${cmakeSuffix}.cmake" \
      --replace "\''${_IMPORT_PREFIX}/lib/libLLVM-" "$lib/lib/libLLVM-"
  ''
  + optionalString (stdenv.isDarwin && enableSharedLibraries) ''
    substituteInPlace "$out/lib/cmake/llvm/LLVMExports-${cmakeSuffix}.cmake" \
      --replace "\''${_IMPORT_PREFIX}/lib/libLLVM.dylib" "$lib/lib/libLLVM.dylib"
    ln -s $lib/lib/libLLVM.dylib $lib/lib/libLLVM-${shortVersion}.dylib
    ln -s $lib/lib/libLLVM.dylib $lib/lib/libLLVM-${release_version}.dylib
  '';

  # TODO
  doCheck = stdenv.isLinux && (!stdenv.isx86_32) && (!stdenv.hostPlatform.isMusl) && false;

  checkTarget = "check-all";

  requiredSystemFeatures = [ "big-parallel" ];
  meta = {
    description = "Collection of modular and reusable compiler and toolchain technologies";
    longDescription = ''
      Rust's LLVM, with extra patches supporting Geobacter.
    '';
    homepage    = "https://github.com/geobacter-rs/geobacter";
    license     = lib.licenses.ncsa;
    maintainers = with lib.maintainers; [ DiamondLovesYou ];
    platforms   = lib.platforms.all;
  };
} // lib.optionalAttrs enableManpages {
  pname = "llvm-manpages";

  buildPhase = ''
    make docs-llvm-man
  '';

  propagatedBuildInputs = [];

  installPhase = ''
    make -C docs install
  '';

  postPatch = null;
  postInstall = null;

  outputs = [ "out" ];

  doCheck = false;

  meta.description = "man pages for LLVM ${version}";
})
