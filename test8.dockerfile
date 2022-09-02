FROM rustdocker/rust:nightly as cargo-build 
# FROM rust:1.62 as cargo-build 
RUN apt-get update 
RUN apt-get install apt-utils -y 
RUN apt-get update 
RUN apt-get install musl-tools -y 
RUN /root/.cargo/bin/rustup target add x86_64-unknown-linux-musl 
RUN USER=root /root/.cargo/bin/cargo new --bin test-rust-hyper 
# RUN mkdir test-rust-hyper 
WORKDIR /test-rust-hyper 
# RUN mkdir src && echo "fn main() {}" > src/main.rs
COPY ./Cargo.toml .
# COPY ./Cargo.lock ./Cargo.lock 
# RUN RUSTFLAGS=-Clinker=musl-gcc /root/.cargo/bin/cargo build --release --target=x86_64-unknown-linux-musl --features vendored 
RUN RUSTFLAGS=-Clinker=musl-gcc /root/.cargo/bin/cargo build --release --target=x86_64-unknown-linux-musl
RUN rm -f target/x86_64-unknown-linux-musl/release/deps/test_rust_hyper* 
# RUN rm src/*.rs 
COPY ./src ./src 
# RUN RUSTFLAGS=-Clinker=musl-gcc /root/.cargo/bin/cargo build --release --target=x86_64-unknown-linux-musl --features vendored 
RUN RUSTFLAGS=-Clinker=musl-gcc /root/.cargo/bin/cargo build --release --target=x86_64-unknown-linux-musl

FROM alpine:latest 
COPY --from=cargo-build /test-rust-hyper/target/x86_64-unknown-linux-musl/release/test-rust-hyper . 

EXPOSE 5555

CMD ["./test-rust-hyper"]