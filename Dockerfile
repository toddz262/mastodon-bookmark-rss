FROM node:20-alpine3.18 as frontend-builder

WORKDIR /app
COPY yarn.lock package.json buildscript.js ./
COPY src ./src/
RUN yarn install --pure-lockfile
RUN yarn build

FROM rust:1.72-alpine3.18 as builder

RUN mkdir -p ~/.cargo && \
    echo '[registries.crates-io]' > ~/.cargo/config && \
    echo 'protocol = "sparse"' >> ~/.cargo/config

RUN apk add --no-cache libc-dev

RUN USER=root cargo new --bin /app
WORKDIR /app

# Just copy the Cargo.toml files and trigger
# a build so that we compile our dependencies only.
# This way we avoid layer cache invalidation
# if our dependencies haven't changed,
# resulting in faster builds.

COPY Cargo.toml .
COPY Cargo.lock .
RUN cargo build --release && rm -rf src/
RUN strip target/release/mastodon-bookmark-rss

# Copy the source code and run the build again.
# This should only compile the app itself as the
# dependencies were already built above.
COPY . ./
COPY --from=frontend-builder /app/build/ /app/build/
RUN rm ./target/release/deps/mastodon_bookmark_rss* && cargo build --release

# Our production image starts here, which uses
# the files from the builder image above.
FROM alpine:3.18

COPY --from=builder /app/target/release/mastodon-bookmark-rss /usr/local/bin/mastodon-bookmark-rss

RUN apk add --no-cache tini

RUN addgroup -S app && adduser -S app -G app
USER app

ENTRYPOINT ["/sbin/tini", "--", "mastodon-bookmark-rss"]
EXPOSE 3000
