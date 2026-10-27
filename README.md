# bun-flake

A Nix flake that provides [Bun](https://bun.com), the JavaScript runtime, bundler, test runner and package manager, from [upstream release binaries](https://github.com/oven-sh/bun/releases).

## What it publishes

`packages.<system>.bun`, and the same package again as `packages.<system>.default`. Its `bin/` holds:

| Program                                          | What it is                                                                                                        |
| ------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------- |
| `bun`                                            | the Bun command line                                                                                              |
| `bunx`                                           | `bun` under its `bunx` name                                                                                       |
| `bun-restore-compiled-interpreter EXECUTABLE...` | rewrite a `bun build --compile` output back to the FHS loader — see [Compiled executables](#compiled-executables) |

## Consuming it

```nix
inputs.bun.url = "github:jgus-org/bun-flake";
```

then use `bun.packages.${system}.bun` wherever you would name an ordinary package, for instance in `nativeBuildInputs`. The flake itself pulls in `nixpkgs` and `flake-lib`; following those inputs into the consumer's own copies keeps a single nixpkgs and a single flake-lib in the evaluation.

## Platform support

`x86_64-linux` only, which is also what the package's `meta.platforms` states. The packaged artifact is upstream's `bun-linux-x64-baseline` release asset.

## Runtime assumptions

`bin/bun` is a launcher, not the upstream executable. On first use it materialises a private copy of the Bun binary and runs that copy:

- The copy lives under `${TMPDIR:-/tmp}`, in directories named after the calling user, the dynamic loader it was built against and the Bun version, so each user/loader/version combination keeps one copy for reuse. Concurrent first uses are serialised, and a copy left half-written by an interrupted run is discarded by the next one.
- `${TMPDIR:-/tmp}` must exist, be absolute and be writable, or Bun does not start.
- The copy is rewritten to run through the dynamic loader Nix provides, so Bun needs no `/lib64/ld-linux-x86-64.so.2` on the host.
- The launcher exits non-zero rather than falling back when those paths are not its own private, owner-only directory or its loader symlink points somewhere else.

## Compiled executables

`bun build --compile` records the loader path of the Bun that produced it. An executable compiled by this package therefore names the launcher's private `/tmp/bun-*/ld-linux.so` and runs only where that launcher has already been used by the same user. `bun-restore-compiled-interpreter` rewrites the interpreter back to `/lib64/ld-linux-x86-64.so.2`, which is what you want before an executable leaves the build; the destination then has to supply that path itself.

The rewrite is checked rather than blind: the tool exits non-zero unless the executable's interpreter is exactly the one this package writes and the private loader directory is present, so run it on the build host as the same user, immediately after the build.

## Licence

Upstream Bun is MIT-licensed; the package's `meta.license` is `lib.licenses.mit`.
