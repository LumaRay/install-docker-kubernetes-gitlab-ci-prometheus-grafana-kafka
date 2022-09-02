FROM clux/muslrust as builder

RUN apt-get update && apt-get install -y ca-certificates

RUN rustup target add x86_64-unknown-linux-musl

WORKDIR /app

# Copy just the Cargo.toml/Cargo.lock over, so source code changes don't 
# invalidate the cached layers
COPY Cargo.toml .
# COPY Cargo.lock .

# Build the deps only by building a binary with an empty main
RUN mkdir -p src \
  # write out our empty entry point
  && echo "fn main() {}" > src/noop.rs \ 
  # add the binary target to Cargo.toml
  && echo "[[bin]]\nname = \"dep-builder\"\npath = \"src/noop.rs\"" >> Cargo.toml \
  # Build just the noop binary
  && cargo build --release --bin dep-builder --target x86_64-unknown-linux-musl


# Copy the actual source code over
COPY src/ src/

# Build the binary
RUN cargo build --release --target x86_64-unknown-linux-musl

FROM scratch

WORKDIR /app

# Copy the SSL certs over
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy just the binary over
COPY --from=builder \
  /app/target/x86_64-unknown-linux-musl/release/test-rust-hyper ./

CMD ["/app/test-rust-hyper"]
