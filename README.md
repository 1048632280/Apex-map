# Apex Map

![Apex Map](public/image/worlds-edge-official.webp)

A lightweight Apex Legends ranked map rotation dashboard.

## Features

- Current ranked map
- Next map with its rotation time range
- Three-map rotation timeline
- Countdown timer with progress ring
- 24-hour time format
- Responsive layout for mobile devices
- iOS home screen and PWA support

## Quick Start

### Docker Compose

```bash
docker compose -f docker/docker-compose.yml pull
docker compose -f docker/docker-compose.yml up -d
```

```yaml
services:
  apex-map-go:
    image: ghcr.io/1048632280/apex-map-go:latest
    container_name: apex-map-go
    restart: unless-stopped
    ports:
      - "127.0.0.1:4173:4173"
```

The application is available at `http://localhost:4173`.

### Build From Source

Requires Go 1.25 or later.

```bash
go run ./server
```

## Data

Rotation data is provided by [ApexRanked](https://apexranked.com/api/ranked-map).

## License

This project is licensed under the [MIT License](LICENSE).

Apex Legends and related assets are trademarks and property of Electronic Arts Inc. This project is not affiliated with or endorsed by Electronic Arts Inc.
