FROM golang:1.25-alpine AS builder

WORKDIR /src

ARG TARGETOS
ARG TARGETARCH

COPY go.mod main.go ./
COPY index.html styles.css app.js manifest.webmanifest ./
COPY image ./image

RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} go build -trimpath -ldflags="-s -w" -o /out/apex-map .

FROM alpine:3.22

WORKDIR /app

RUN addgroup -S app && adduser -S -G app app

COPY --from=builder /out/apex-map /app/apex-map

ENV PORT=4173

EXPOSE 4173

USER app

CMD ["/app/apex-map"]
