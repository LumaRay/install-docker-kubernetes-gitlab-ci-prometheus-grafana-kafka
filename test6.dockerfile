FROM rust:1.62 AS builder
# FROM ekidd/rust-musl-builder:stable as builder

RUN USER=root cargo new --bin test-rust-hyper
WORKDIR ./test-rust-hyper
COPY ./Cargo.lock ./Cargo.lock
COPY ./Cargo.toml ./Cargo.toml
RUN cargo build --release
RUN rm src/*.rs

ADD . ./

# RUN rm ./target/x86_64-unknown-linux-musl/release/deps/test_rust_hyper*
RUN cargo build --release


FROM scratch

ARG APP=/usr/src/app

EXPOSE 5555

ENV TZ=Etc/UTC \
    APP_USER=appuser

# RUN addgroup -S $APP_USER \
    # && adduser -S -g $APP_USER $APP_USER

# RUN apk update \
    # && apk add --no-cache ca-certificates tzdata \
    # && rm -rf /var/cache/apk/*

# COPY --from=builder /home/rust/src/test-rust-hyper/target/x86_64-unknown-linux-musl/release/test-rust-hyper ${APP}/test-rust-hyper
COPY --from=builder /test-rust-hyper/target/release/test-rust-hyper ${APP}/test-rust-hyper

# RUN chown -R $APP_USER:$APP_USER ${APP}

# USER $APP_USER
WORKDIR ${APP}

CMD ["./test-rust-hyper"]