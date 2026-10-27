{
  description = "Bun JavaScript runtime and compiler from upstream release binaries";

  inputs = {
    flake-lib.url = "github:jgus-org/flake-lib/v1";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    {
      self,
      flake-lib,
      nixpkgs,
      ...
    }:
    let
      pin = import ./pin.nix;
      source = {
        owner = "oven-sh";
        repo = "bun";
        tagPrefix = "bun-v";
        type = "github";
      };
    in
    flake-lib.lib.eachSystem [ "x86_64-linux" ] (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
        inherit (pkgs) lib;
        orgFormatting = flake-lib.lib.mkFormatting {
          inherit self system;
        };
        assetName = "bun-linux-x64-baseline.zip";
        archive = pkgs.fetchurl {
          hash = pin.assetHash or "";
          url = "https://github.com/${source.owner}/${source.repo}/releases/download/bun-v${pin.version}/${assetName}";
        };
        bunUnpatched = pkgs.stdenvNoCC.mkDerivation {
          inherit (pin) version;
          dontBuild = true;
          dontConfigure = true;
          dontPatchELF = true;
          dontStrip = true;
          installPhase = ''
            runHook preInstall
            install -Dm755 bun $out/bin/bun
            runHook postInstall
          '';
          nativeBuildInputs = [ pkgs.unzip ];
          pname = "bun-unpatched";
          sourceRoot = "bun-linux-x64-baseline";
          src = archive;
        };
        bunWrapper = pkgs.writeShellScript "bun" ''
          set -euo pipefail
          uid="$(${pkgs.coreutils}/bin/id -u)"
          alias_token="$(printf '%s' "$uid:${pkgs.stdenv.cc.bintools.dynamicLinker}" | ${pkgs.coreutils}/bin/sha256sum)"
          bun_dir="/tmp/bun-''${alias_token:0:6}"
          bun_loader="$bun_dir/ld-linux.so"
          cache_root="''${TMPDIR:-/tmp}"
          [[ "$cache_root" == /* && -d "$cache_root" ]] || exit 1
          cache_dir="$cache_root/bun-cache-''${alias_token:0:6}"
          bun_runtime="$cache_dir/${builtins.baseNameOf (toString bunUnpatched)}"
          ${pkgs.coreutils}/bin/mkdir -p -m 700 "$bun_dir"
          [[ -d "$bun_dir" && ! -L "$bun_dir" && "$(${pkgs.coreutils}/bin/stat -c '%u:%a' "$bun_dir")" == "$uid:700" ]] || exit 1
          if [[ ! -e "$bun_loader" && ! -L "$bun_loader" ]]; then
            ${pkgs.coreutils}/bin/ln -s ${pkgs.stdenv.cc.bintools.dynamicLinker} "$bun_loader" 2>/dev/null || true
          fi
          [[ -L "$bun_loader" && "$(${pkgs.coreutils}/bin/readlink "$bun_loader")" == ${pkgs.stdenv.cc.bintools.dynamicLinker} ]] || exit 1
          ${pkgs.coreutils}/bin/mkdir -m 700 "$cache_dir" 2>/dev/null || true
          [[ -d "$cache_dir" && ! -L "$cache_dir" && "$(${pkgs.coreutils}/bin/stat -c '%u:%a' "$cache_dir")" == "$uid:700" ]] || exit 1
          exec 9<"$cache_dir"
          ${pkgs.util-linux}/bin/flock 9
          for abandoned in "$bun_runtime".staging.??????; do
            [[ -e "$abandoned" || -L "$abandoned" ]] || continue
            [[ -f "$abandoned" && ! -L "$abandoned" && "$(${pkgs.coreutils}/bin/stat -c '%u' "$abandoned")" == "$uid" ]] || exit 1
            ${pkgs.coreutils}/bin/rm -- "$abandoned"
          done
          [[ ! -L "$bun_runtime" ]] || exit 1
          if [[ ! -e "$bun_runtime" ]]; then
            bun_tmp="$(${pkgs.coreutils}/bin/mktemp "$bun_runtime.staging.XXXXXX")"
            trap '${pkgs.coreutils}/bin/rm -f "$bun_tmp"' EXIT
            ${pkgs.gnused}/bin/sed "s|/lib64/ld-linux-x86-64[.]so[.]2|$bun_loader|" ${bunUnpatched}/bin/bun > "$bun_tmp"
            ${pkgs.coreutils}/bin/chmod 755 "$bun_tmp"
            [[ "$(${pkgs.patchelf}/bin/patchelf --print-interpreter "$bun_tmp")" == "$bun_loader" ]] || exit 1
            ${pkgs.coreutils}/bin/mv -T "$bun_tmp" "$bun_runtime"
          fi
          [[ -f "$bun_runtime" && ! -L "$bun_runtime" && "$(${pkgs.coreutils}/bin/stat -c '%u:%a' "$bun_runtime")" == "$uid:755" ]] || exit 1
          [[ "$(${pkgs.patchelf}/bin/patchelf --print-interpreter "$bun_runtime")" == "$bun_loader" ]] || exit 1
          exec 9>&-
          exec -a "$0" "$bun_runtime" "$@"
        '';
        restoreCompiledInterpreter = pkgs.writeShellScript "bun-restore-compiled-interpreter" ''
          set -euo pipefail
          if (( $# == 0 )); then
            echo "usage: bun-restore-compiled-interpreter EXECUTABLE..." >&2
            exit 2
          fi
          uid="$(${pkgs.coreutils}/bin/id -u)"
          alias_token="$(printf '%s' "$uid:${pkgs.stdenv.cc.bintools.dynamicLinker}" | ${pkgs.coreutils}/bin/sha256sum)"
          bun_dir="/tmp/bun-''${alias_token:0:6}"
          bun_loader="$bun_dir/ld-linux.so"
          [[ -d "$bun_dir" && ! -L "$bun_dir" && "$(${pkgs.coreutils}/bin/stat -c '%u:%a' "$bun_dir")" == "$uid:700" ]] || exit 1
          [[ -L "$bun_loader" && "$(${pkgs.coreutils}/bin/readlink "$bun_loader")" == ${pkgs.stdenv.cc.bintools.dynamicLinker} ]] || exit 1
          for executable in "$@"; do
            [[ "$(${pkgs.patchelf}/bin/patchelf --print-interpreter "$executable")" == "$bun_loader" ]] || exit 1
            ${pkgs.gnused}/bin/sed -i "s|/tmp/bun-''${alias_token:0:6}/ld-linux[.]so|/lib64/ld-linux-x86-64.so.2|" "$executable"
          done
        '';
        bun =
          pkgs.runCommand "bun-${pin.version}"
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
        artifactHook = lib.getExe (
          pkgs.writeShellApplication {
            name = "bun-release-artifacts";
            runtimeInputs = [
              pkgs.jq
              pkgs.nix
            ];
            text = ''
              ASSET_HASH="$(nix store prefetch-file --json --hash-type sha256 "https://github.com/oven-sh/bun/releases/download/bun-v''${NEW_VERSION}/${assetName}" | jq -r .hash)"
              printf 'assetHash=%s\n' "''${ASSET_HASH}"
            '';
          }
        );
        updateVersion = flake-lib.lib.mkUpdateVersion {
          inherit artifactHook pkgs source;
          extraHashes = [ "assetHash" ];
        };
      in
      {
        checks = {
          bun = bun;
          formatting = orgFormatting.check;
        };
        formatter = orgFormatting.formatter;
        packages = {
          inherit bun;
          default = bun;
          update-branches = flake-lib.lib.mkUpdateBranches {
            inherit pkgs source;
            extraHashes = [ "assetHash" ];
            minimumTrackingVersion = "1.3.14";
            pinSchema = "github";
          };
          update-version = pkgs.writeShellApplication {
            name = "update-version";
            runtimeInputs = [ pkgs.nix ];
            text = ''
              ${lib.getExe updateVersion} "$@"
              nix build --option post-build-hook "" --no-link "''${FLAKE_ROOT:-$PWD}#bun"
            '';
          };
        };
      }
    );
}
