# Build Stage
FROM ghcr.io/evanrichter/cargo-fuzz:latest as builder

## Add source code to the build stage.
ADD . /src
WORKDIR /src

RUN echo building instrumented harnesses && \
    bash -c "pushd crates/typos/fuzz && cargo +nightly -Z sparse-registry fuzz build && popd" && \
    bash -c "pushd crates/varcon-core/fuzz && cargo +nightly -Z sparse-registry fuzz build && popd" && \
    mv crates/typos/fuzz/target/x86_64-unknown-linux-gnu/release/tokenizer /tokenizer && \
    mv crates/varcon-core/fuzz/target/x86_64-unknown-linux-gnu/release/cluster_parse /cluster_parse && \
    echo done

RUN echo building non-instrumented harnesses && \
    export RUSTFLAGS="--cfg fuzzing -Clink-dead-code -Cdebug-assertions -C codegen-units=1" && \
    bash -c "pushd crates/typos/fuzz && cargo +nightly -Z sparse-registry build --release && popd" && \
    bash -c "pushd crates/varcon-core/fuzz && cargo +nightly -Z sparse-registry build --release && popd" && \
    mv crates/typos/fuzz/target/release/tokenizer /tokenizer_no_inst && \
    mv crates/varcon-core/fuzz/target/release/cluster_parse /cluster_parse_no_inst && \
    echo done

# Package Stage
FROM rustlang/rust:nightly

COPY --from=builder /tokenizer /tokenizer_no_inst /
COPY --from=builder /cluster_parse /cluster_parse_no_inst /
