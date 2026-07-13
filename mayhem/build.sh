#!/usr/bin/env bash
#
# typos/mayhem/build.sh — build crate-ci/typos' cargo-fuzz targets as sanitized
# libFuzzer binaries (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS).
#
# ASan is enabled the Rust way, through RUSTFLAGS `-Zsanitizer=address` — NOT via
# clang's $SANITIZER_FLAGS / CFLAGS (those don't apply to rustc); this is what
# OSS-Fuzz's `compile` sets for FUZZING_LANGUAGE=rust. nightly is required.
#
# Targets (both preserved from the fork's original Mayhem integration, which added
# them under crates/*/fuzz; upstream never carried those dirs, so they live here as
# an additive mayhem/fuzz crate driving the SAME entry points):
#   tokenizer     — typos::tokens::Tokenizer::parse_bytes/parse_str (the identifier
#                   tokenizer at the heart of the spell-checker)
#   cluster_parse — varcon_core::ClusterIter (the varcon dictionary cluster parser)
#
# Also builds the workspace TEST suite (normal flags, no sanitizer) so mayhem/test.sh
# only RUNS it.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# DWARF < 4 debug-info contract (§6.2 item 10): force DWARF 2 so Mayhem triage can
# resolve project source lines. The rlenv runtime may export RUST_DEBUG_FLAGS before
# re-running build.sh offline; the := default only applies when unset/empty.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=--dwarf-version=2}"

cd "$SRC"

# Rust's ASan runtime is compiled with the nightly's bundled LLVM (DWARF 5) and links
# BEFORE project code, so the first .debug_info CU would be DWARF 5. Strip its debug
# sections once; project code (DWARF 2 via RUST_DEBUG_FLAGS) then appears first.
ASAN_RT="$(find "$RUSTUP_HOME/toolchains" -name "librustc-nightly_rt.asan.a" 2>/dev/null | head -1)"
if [ -n "$ASAN_RT" ] && [ -f "$ASAN_RT" ]; then
    echo "Stripping debug info from Rust ASan runtime to enforce DWARF < 4: $ASAN_RT"
    objcopy --strip-debug "$ASAN_RT"
fi

# libfuzzer-sys compiles libFuzzer from C++ via the cc crate; force DWARF 3 there too.
export CFLAGS="${CFLAGS:+$CFLAGS }-gdwarf-3"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }-gdwarf-3"

FUZZ_DIR="mayhem/fuzz"
FUZZ_TARGETS=(tokenizer cluster_parse)
TRIPLE="x86_64-unknown-linux-gnu"

# OSS-Fuzz Rust libFuzzer+ASan flags; --cfg fuzzing matches libfuzzer-sys.
export RUSTFLAGS="${RUSTFLAGS:-} --cfg fuzzing -Zsanitizer=address ${RUST_DEBUG_FLAGS}"

echo "=== cargo fuzz build (image-default nightly toolchain, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"

for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
done

TARGET_DIR="$(cargo metadata --no-deps --format-version 1 --manifest-path "$FUZZ_DIR/Cargo.toml" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["target_directory"])')"
echo "fuzz target_directory: $TARGET_DIR"

REL="$TARGET_DIR/$TRIPLE/release"
for t in "${FUZZ_TARGETS[@]}"; do
  bin="$REL/$t"
  if [ ! -x "$bin" ]; then
    echo "ERROR: expected fuzz binary not found at $bin" >&2
    ls -la "$REL" >&2 || true
    exit 1
  fi
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# Build the workspace TEST suite with the project's NORMAL flags (no sanitizer
# RUSTFLAGS) so mayhem/test.sh only RUNS the pre-built tests.
echo "=== building the workspace test suite (normal flags, no sanitizers) ==="
RUSTFLAGS="" cargo test --workspace --no-run --jobs "$MAYHEM_JOBS"

echo "build.sh complete:"
ls -la /mayhem/tokenizer /mayhem/cluster_parse
