{ lib, stdenv, rustPlatform, Security, vendorSha256 }:

rustPlatform.buildRustPackage rec {
  pname = "geobacter-rustfmt";
  inherit (rustPlatform.rust.rustc) version src cargoDeps;

  cargoSha256 = vendorSha256;
  postUnpack = ''
    (mkdir source/vendor && cd source/vendor && tar xf "${rustPlatform.rust.rustc.cargoDeps}" --strip-components=1);
  '';
  buildAndTestSubdir = "src/tools/rustfmt";

  # changes hash of vendor directory otherwise
  dontUpdateAutotoolsGnuConfigScripts = true;

  buildInputs = lib.optional stdenv.isDarwin Security;

  # As of 1.0.0 and rustc 1.30 rustfmt requires a nightly compiler
  RUSTC_BOOTSTRAP = 1;

  # As of rustc 1.45.0, these env vars are required to build rustfmt (due to
  # https://github.com/rust-lang/rust/pull/72001)
  CFG_RELEASE = "${rustPlatform.rust.rustc.version}-nightly";
  CFG_RELEASE_CHANNEL = "nightly";

  meta = with lib; {
    description = "A tool for formatting Rust code according to style guidelines";
    homepage = "https://github.com/rust-lang-nursery/rustfmt";
    longDescription = ''
      Exactly like upstream rustfmt, built with Geobacter.
    '';
    maintainers = with maintainers; [ DiamondLovesYou ];
    license = with licenses; [ mit asl20 ];
  };
}
