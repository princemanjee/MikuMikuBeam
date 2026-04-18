# syntax=docker/dockerfile:1.7

# --- Stage 1: build web client ---------------------------------------------
FROM node:20-alpine AS webbuilder
WORKDIR /src/web-client

COPY web-client/package.json web-client/package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY web-client/ ./
RUN npm run build

# --- Stage 2: build Go server ----------------------------------------------
FROM golang:1.24-alpine AS gobuilder
WORKDIR /src

RUN apk add --no-cache git

COPY go.mod go.sum ./
RUN go mod download

COPY cmd/ ./cmd/
COPY internal/ ./internal/
COPY pkg/ ./pkg/

ENV CGO_ENABLED=0 GOOS=linux
RUN go build -trimpath -ldflags="-s -w" -o /out/mmb-server ./cmd/mmb-server

# --- Stage 3: runtime ------------------------------------------------------
FROM alpine:3.20
WORKDIR /app

RUN apk add --no-cache ca-certificates tini \
    && addgroup -S mmb && adduser -S -G mmb mmb \
    && mkdir -p /app/bin/web-client /app/data \
    && chown -R mmb:mmb /app

COPY --from=gobuilder  /out/mmb-server                 /app/bin/mmb-server
COPY --from=webbuilder /src/web-client/dist/public/    /app/bin/web-client/

RUN touch /app/data/proxies.txt /app/data/uas.txt \
    && chown -R mmb:mmb /app/data /app/bin

USER mmb

ENV ALLOW_NO_PROXY=true \
    LOG_FORMAT=console

EXPOSE 3000
VOLUME ["/app/data"]

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/app/bin/mmb-server"]
