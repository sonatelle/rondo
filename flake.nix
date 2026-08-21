{
  description = "Rust project shell via Sonatelle Prelude";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
    prelude.url = "github:sonatelle/prelude";
    # Share this project's nixpkgs with Prelude (and its nested devshell).
    prelude.inputs.nixpkgs.follows = "nixpkgs";
    prelude.inputs.flake-parts.follows = "flake-parts";

    # Required by flakeModules.rust (not part of flakeModules.default).
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        inputs.prelude.flakeModules.default
        inputs.prelude.flakeModules.rust
      ];

      # nixos-unstable no longer supports x86_64-darwin (dropped in 26.11).
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];

      perSystem = {pkgs, ...}: {
        prelude = {
          enable = true;
          name = "rust";

          languages.rust = {
            enable = true;
            # version = "stable";                      # default
            version = "1.97.1";
            targets = [
              "aarch64-apple-darwin"
            ];
            # version = "file"; toolchainFile = ./rust-toolchain.toml;
            # packages = [ ];                          # extra nixpkgs packages
            # tools.bacon.enable = false;              # per built-in tool switches
            # tools.deny.enable = true;                # cargo-deny (default off)
          };

          packages = [
            pkgs.shfmt
            pkgs.swiftformat
          ];
        };
      };
    };
}
