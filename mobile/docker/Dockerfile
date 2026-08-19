# syntax=docker/dockerfile:1

FROM debian:bookworm-slim AS flutter-base

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl git unzip xz-utils zip ca-certificates libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

ARG FLUTTER_VERSION=3.47.0
RUN git clone https://github.com/flutter/flutter.git -b ${FLUTTER_VERSION} --depth 1 /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

RUN git config --global --add safe.directory /usr/local/flutter \
    && flutter config --enable-web --no-analytics \
    && flutter precache --web \
    && flutter doctor -v

WORKDIR /app


# ---- dev: hot-reloadable web server, source is bind-mounted at runtime ----
FROM flutter-base AS dev

ARG BACKEND_URL
ENV BACKEND_URL=${BACKEND_URL}

COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY . .

EXPOSE 3000
CMD ["flutter", "run", "-d", "web-server", "--web-hostname", "0.0.0.0", "--web-port", "3000"]


# ---- build: compile a release web bundle ----
FROM flutter-base AS build

ARG BACKEND_URL
ENV BACKEND_URL=${BACKEND_URL}

COPY pubspec.yaml pubspec.lock* ./
RUN flutter pub get

COPY . .
RUN flutter build web --release --dart-define=BACKEND_URL=${BACKEND_URL}

