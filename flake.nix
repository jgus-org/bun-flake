{
  description = "Bun JavaScript runtime and compiler from upstream release binaries";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    flake-lib = {
      url = "github:jgus-org/flake-lib/v1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { nixpkgs, flake-utils, flake-lib, ... }:
    let
      pin = import ./pin.nix;
      source = {
        type = "github";
        owner = "oven-sh";
        repo = "bun";
        tagPrefix = "bun-v";
      };
    in
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;
        assetName = "bun-linux-x64-baseline.zip";
        archive = pkgs.fetchurl {
          url = "https://github.com/${source.owner}/${source.repo}/releases/download/bun-v${pin.version}/${assetName}";
          hash = pin.assetHash or "";
        };
        bunUnpatched = pkgs.stdenvNoCC.mkDerivation {
          pname = "bun-unpatched";
          inherit (pin) version;
          src = archive;
          sourceRoot = "bun-linux-x64-baseline";
          nativeBuildInputs = [ pkgs.unzip ];
          dontConfigure = true;
          dontBuild = true;
          dontPatchELF = true;
          dontStrip = true;
          installPhase = ''
            runHook preInstall
            install -Dm755 bun $out/bin/bun
            runHook postInstall
          '';
        };
        # Bun copies its own ELF layout into compiled executables. Keep its bytes pristine, changing only the equal-length interpreter string in a temporary copy while compiling; consumers restore the standard nix-ld path after their installed-binary checks.
        bunWrapper = pkgs.writeShellScript "bun" ''
          bun_runtime="''${TMPDIR:-/tmp}/bun-${pin.version}"
          if [[ ! -x "''${bun_runtime}" ]]; then
            ${pkgs.coreutils}/bin/cp ${bunUnpatched}/bin/bun "''${bun_runtime}"
            ${pkgs.coreutils}/bin/chmod u+w "''${bun_runtime}"
            ${pkgs.gnused}/bin/sed -i 's|/lib64/ld-linux-x86-64.so.2|/build/bunld-linux-x64.so.2|' "''${bun_runtime}"
          fi
          ${pkgs.coreutils}/bin/ln -sf ${pkgs.stdenv.cc.bintools.dynamicLinker} /build/bunld-linux-x64.so.2
          exec "''${bun_runtime}" "$@"
        '';
        restoreCompiledInterpreter = pkgs.writeShellScript "bun-restore-compiled-interpreter" ''
          set -euo pipefail
          if (( $# == 0 )); then
            echo "usage: bun-restore-compiled-interpreter EXECUTABLE..." >&2
            exit 2
          fi
          for executable in "$@"; do
            ${pkgs.gnused}/bin/sed -i 's|/build/bunld-linux-x64.so.2|/lib64/ld-linux-x86-64.so.2|' "$executable"
          done
        '';
        bun = pkgs.runCommand "bun-${pin.version}"
          {
            inherit (pin) version;
            meta = {
              description = "Incredibly fast JavaScript runtime, bundler, test runner, and package manager";
              homepage = "https://bun.com";
              license = lib.licenses.mit;
              mainProgram = "bun";
              platforms = [ "x86_64-linux" ];
            };
          }
          ''
            mkdir -p $out/bin
            ln -s ${bunWrapper} $out/bin/bun
            ln -s bun $out/bin/bunx
            ln -s ${restoreCompiledInterpreter} $out/bin/bun-restore-compiled-interpreter
            test "$($out/bin/bun --version)" = "${pin.version}"
          '';
        artifactHook = lib.getExe (pkgs.writeShellApplication {
          name = "bun-release-artifacts";
          runtimeInputs = [
            pkgs.jq
            pkgs.nix
          ];
          text = ''
            ASSET_HASH="$(nix store prefetch-file --json --hash-type sha256 "https://github.com/oven-sh/bun/releases/download/bun-v''${NEW_VERSION}/${assetName}" | jq -r .hash)"
            printf 'assetHash=%s\n' "''${ASSET_HASH}"
          '';
        });
        updateVersion = flake-lib.lib.mkUpdateVersion {
          inherit pkgs source artifactHook;
          buildAttr = "bun";
          extraHashes = [ "assetHash" ];
          verification = "build";
        };
      in
      {
        packages = {
          inherit bun;
          default = bun;
          update-version = pkgs.writeShellApplication {
            name = "update-version";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              ${lib.getExe updateVersion} "$@"
              nix build --option post-build-hook "" --no-link "''${FLAKE_ROOT:-$PWD}#bun"
            '';
          };
          update-branches = flake-lib.lib.mkUpdateBranches {
            inherit pkgs source;
            pinSchema = "github";
            extraHashes = [ "assetHash" ];
          };
        };
        checks.bun = bun;
      });
}
