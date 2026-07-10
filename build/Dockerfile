FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates build-essential libsqlite3-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 https://github.com/felt/tippecanoe.git /src \
    && make -C /src -j4 && make -C /src install

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-0 zlib1g && rm -rf /var/lib/apt/lists/*
COPY --from=build /usr/local/bin/tippecanoe /usr/local/bin/tile-join /usr/local/bin/tippecanoe-decode /usr/local/bin/
WORKDIR /data
ENTRYPOINT []
