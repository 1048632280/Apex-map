# Apex Map

![Apex Map](public/image/worlds-edge-official.webp)

A lightweight ranked map rotation dashboard for Apex Legends.

## Features

- Current ranked map
- Next map with its rotation time range
- Three-map rotation timeline
- Countdown timer with progress ring
- 24-hour local time
- Responsive layout for mobile devices
- iOS home screen and PWA support

## Quick Start

Replace `YOUR_APEX_LEGENDS_STATUS_API_KEY` with your Apex Legends Status API key.

```yaml
version: "3"

services:
  apex-map-go:
    image: ghcr.io/1048632280/apex-map-go:latest
    container_name: apex-map-go
    restart: unless-stopped
    environment:
      APEX_LEGENDS_STATUS_API_KEY: "YOUR_APEX_LEGENDS_STATUS_API_KEY"
    ports:
      - "127.0.0.1:4173:4173"
    volumes:
      - apex-map-data:/app/data

volumes:
  apex-map-data:
```

```bash
docker compose -f docker/docker-compose.yml pull
docker compose -f docker/docker-compose.yml up -d
```

Open `http://localhost:4173`.

## Build From Source

Requires Go 1.25 or later.

```bash
APEX_LEGENDS_STATUS_API_KEY="YOUR_APEX_LEGENDS_STATUS_API_KEY" go run ./server
```

## Data

Rotation data is provided by [Apex Legends Status](https://apexlegendsstatus.com/).

## License

This project is licensed under the [MIT License](LICENSE).

Apex Legends and related assets are trademarks and property of Electronic Arts Inc. This project is not affiliated with or endorsed by Electronic Arts Inc.
