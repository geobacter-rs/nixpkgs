{ stdenv, fetchurl, geobacterRust, callPackage, version, date, hashes }:

let
  platform = geobacterRust.toRustTarget stdenv.hostPlatform;

  src = fetchurl {
     url = "https://static.rust-lang.org/dist/${date}/rust-beta-${platform}.tar.gz";
     sha256 = hashes.${platform} or (throw "missing bootstrap url for platform ${platform}");
  };

in callPackage ./binary.nix
  { inherit version src platform;
    versionType = "bootstrap";
  }
