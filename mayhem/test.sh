#!/usr/bin/env bash
#
# typos/mayhem/test.sh — RUN crate-ci/typos' own full upstream test suite
# (`cargo test --workspace`) and emit a CTRF summary. exit 0 iff no test failed.
#
# PATCH-grade oracle: the workspace ships its full upstream suite — typos unit
# tests (tokens/check/dict parsing), typos-cli unit + trycmd/snapbox CLI tests
# (golden-output file checks), varcon-core parser tests, dictgen/dict crates'
# codegen + lookup tests. These assert concrete token streams, exact corrected
# output, and golden files, so a no-op / exit(0) patch CANNOT pass. This script
# only RUNS the suite (build.sh pre-compiled it with `cargo test --no-run`).
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

if ! command -v cargo >/dev/null 2>&1; then
  echo "cargo not available — cannot run the test suite" >&2
  emit_ctrf "cargo-test" 0 1 0; exit 2
fi

echo "=== running cargo test --workspace (typos' full upstream suite) ==="
# Same invocation build.sh pre-built (minus --no-run) so nothing recompiles here.
# RUSTFLAGS cleared so it inherits nothing from the sanitizer build.
# LC_ALL=C.UTF-8: typos-cli's trycmd golden files expect the unicode diagnostic
# style, which annotate-snippets only emits under a UTF-8 charset.
out="$(LC_ALL=C.UTF-8 LANG=C.UTF-8 RUSTFLAGS="" cargo test --workspace --no-fail-fast --jobs "$MAYHEM_JOBS" 2>&1)"; rc=$?
echo "$out"

# libtest prints one line per test binary:
#   test result: ok. 31 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; ...
PASSED=0; FAILED=0; IGNORED=0
while read -r p f i; do
  PASSED=$(( PASSED + p )); FAILED=$(( FAILED + f )); IGNORED=$(( IGNORED + i ))
done < <(printf '%s\n' "$out" \
  | sed -n 's/^test result:.* \([0-9][0-9]*\) passed; \([0-9][0-9]*\) failed; \([0-9][0-9]*\) ignored.*/\1 \2 \3/p')

# If we parsed no result lines, something is deeply wrong (compile error, neutered
# toolchain) — report a failure rather than trusting the exit code alone.
if [ "$(( PASSED + FAILED + IGNORED ))" -eq 0 ]; then
  echo "could not parse any 'test result:' lines (cargo rc=$rc)" >&2
  emit_ctrf "cargo-test" 0 1 0; exit 1
fi

# A nonzero cargo rc with all-passing parsed lines means some binary crashed outside
# libtest accounting — count it as a failure.
if [ "$rc" -ne 0 ] && [ "$FAILED" -eq 0 ]; then
  FAILED=1
fi

emit_ctrf "cargo-test" "$PASSED" "$FAILED" "$IGNORED"
