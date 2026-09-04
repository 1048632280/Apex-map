FROM golang:1.25-alpine AS builder

WORKDIR /src

ARG TARGETOS
ARG TARGETARCH

COPY go.mod ./
COPY server ./server

RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} \
    go build -trimpath -ldflags="-s -w" -o /out/apex-map ./server

FROM alpine:3.22

WORKDIR /app

RUN apk add --no-cache ca-certificates && \
    addgroup -S app && \
    adduser -S -G app app

COPY --from=builder /out/apex-map /app/apex-map
COPY public /app/public

EXPOSE 4173

USER app

ENTRYPOINT ["/app/apex-map"]
