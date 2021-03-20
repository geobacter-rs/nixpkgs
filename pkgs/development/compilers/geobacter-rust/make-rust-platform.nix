{ lib, buildPackages, callPackage }:

{ rustc, cargo, rustfmt, ... }:

rec {
  rust = rec {
    inherit rustc cargo rustfmt;
    # https://doc.rust-lang.org/reference/conditional-compilation.html#target_arch
    toTargetArch = platform:
      if platform.isAarch32 then "arm"
      else platform.parsed.cpu.name;

    # https://doc.rust-lang.org/reference/conditional-compilation.html#target_os
    toTargetOs = platform:
      if platform.isDarwin then "macos"
      else platform.parsed.kernel.name;

    # Returns the name of the rust target, even if it is custom. Adjustments are
    # because rust has slightly different naming conventions than we do.
    toRustTarget = platform: with platform.parsed; let
      cpu_ = platform.rustc.platform.arch or {
        "armv7a" = "armv7";
        "armv7l" = "armv7";
        "armv6l" = "arm";
      }.${cpu.name} or cpu.name;
    in platform.rustc.config
      or "${cpu_}-${vendor.name}-${kernel.name}${lib.optionalString (abi.name != "unknown") "-${abi.name}"}";

    # Returns the name of the rust target if it is standard, or the json file
    # containing the custom target spec.
    toRustTargetSpec = platform:
      if (platform.rustc or {}) ? platform
      then builtins.toFile (toRustTarget platform + ".json") (builtins.toJSON platform.rustc.platform)
      else toRustTarget platform;
  };

  fetchCargoTarball = buildPackages.callPackage ../../../build-support/rust/fetchCargoTarball.nix {
    inherit cargo;
  };

  buildRustPackage = callPackage ../../../build-support/rust {
    inherit cargoBuildHook cargoCheckHook cargoInstallHook cargoSetupHook
      fetchCargoTarball rustc;
    inherit rust;
  };

  rustcSrc = callPackage ./rust-src.nix {
    inherit rustc;
  };

  rustLibSrc = callPackage ./rust-lib-src.nix {
    inherit rustc;
  };

  # Hooks
  inherit (callPackage ../../../build-support/rust/hooks {
    inherit cargo;
    inherit rust;
  }) cargoBuildHook cargoCheckHook cargoInstallHook cargoSetupHook maturinBuildHook;
}
