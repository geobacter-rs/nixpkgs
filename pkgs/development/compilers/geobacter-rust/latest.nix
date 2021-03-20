{ stdenv, lib
, buildPackages
, newScope, callPackage
, CoreFoundation, Security
, pkgsBuildTarget, pkgsBuildBuild, pkgsBuildHost
, makeGeobacterRustPlatform
, llvmPackages_5, geobacterLlvm_latest
} @ args:

let
  llvmAttrs = {
    enableSharedLibraries = true;
    enablePolly = true;
    buildType = "RelWithDebInfo";
    enableAssertions = true;
  };
in import ./default.nix {
  rustcVersion = "1.49.0";
  rustcRev = "542f72c09948fd6afd7a67924dcab96ac3bccac9";
  rustcSha256 = "09ph0x3rsgh5ym61mldk3pcvz9700bzp2ynqn7fps84rp2k85359";
  rustcVendorSha256 = "1yxddw91gaz50qrnf1mngr3k7f0gkyxkw0w44mz6n9rsi98kfcdv";
  # Not sure why these are different, since we vender the whole workspace.
  cargoVendorSha256 = "1r13afsqddx40xqz1figi0353zgy909ql5i76446ng70va3xwc22";
  rustfmtVendorSha256 = "05gmgpprqa3kk4n04r51scn3786p9r5hlq561prr67a7fp9zhl7p";

  llvmSharedForBuild = pkgsBuildBuild.geobacterLlvm_latest.override llvmAttrs;
  llvmSharedForHost = pkgsBuildHost.geobacterLlvm_latest.override llvmAttrs;
  llvmSharedForTarget = pkgsBuildTarget.geobacterLlvm_latest.override llvmAttrs;

  # For use at runtime
  llvmShared = geobacterLlvm_latest.override llvmAttrs;

  # ??
  llvmBootstrapForDarwin = llvmPackages_5;

  bootstrapVersion = "1.48.0";
  bootstrapDate = "2020-08-26";
  bootstrapHashes = {
    i686-unknown-linux-gnu = "12fbb3ec76872ba21e92a93c65bd96b57829e0bd1ad442d7e52f038a307cc2ee";
    x86_64-unknown-linux-gnu = "4dd4d81e4150d49a251c587bdbd957a9f2725ab3076383f3e239e6de215aba9f";
    x86_64-unknown-linux-musl = "9a9fcf9217feed9e1aa74133d8fb8262b55d3c0b02ae54c4f5b1dad563730860";
    arm-unknown-linux-gnueabihf = "2bf98dd79d5551a03a8c9b3f82962562447efb0b0f8c904a92e0b5d91c07d769";
    armv7-unknown-linux-gnueabihf = "067d2056905825fc5ec09e84c3de6084dc2238447ceb0d1f3bc385705904f80e";
    aarch64-unknown-linux-gnu = "ff2335436ebb6ef94fd715bd734106fdcd67a6618c735eb7e13114a16df3473c";
    x86_64-apple-darwin = "a427106e60595b1e4dfb2338baff16fae1e7f5350cf54ecd851b594d44044e5a";
    powerpc64le-unknown-linux-gnu = "a1313f37a872c2602ec53e1c724100d269d3d5e81b222bd38c38fe4670582d34";
  };

  selectRustPackage = pkgs: pkgs.geobacterRust_1_49;

  rustcPatches = [
    ./0001-Shutup.patch
  ];
}
(builtins.removeAttrs args [ "fetchpatch" "pkgsBuildHost" "llvmPackages_5" "geobacterLlvm_latest"])
