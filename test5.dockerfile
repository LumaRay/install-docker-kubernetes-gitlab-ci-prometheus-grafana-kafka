FROM rust:1.62 AS build

ADD ./ /hyper
WORKDIR /hyper

RUN cargo clean
RUN RUSTFLAGS="-C target-cpu=native" cargo build --release

EXPOSE 5555

CMD ["/hyper/target/release/test-rust-hyper"]

# FROM scratch AS bin

# COPY --from=build ./target/release/test-rust-hyper /hyper-test