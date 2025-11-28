# Docker Setup for osmo-remsim

This document describes how to build and run osmo-remsim using Docker, with support for USB smart card readers like the Octosim.

## Quick Start

### Build the Docker Image

```bash
# Clone the repository
git clone https://gitea.osmocom.org/sim-card/osmo-remsim
cd osmo-remsim

# Build the Docker image
docker build -t osmo-remsim .
```

### Run the Server

```bash
# Start the remsim-server
docker run -d --name remsim-server \
  -p 9997:9997 \
  -p 9998:9998 \
  osmo-remsim server
```

### Run the Bank Daemon (with USB Octosim Reader)

```bash
# Start the bankd with USB access
docker run -d --name remsim-bankd \
  --privileged \
  -v /dev/bus/usb:/dev/bus/usb \
  -e REMSIM_SERVER_HOST=192.168.1.100 \
  -e REMSIM_NUM_SLOTS=8 \
  osmo-remsim bankd
```

## Docker Compose

For easier management, use Docker Compose:

```bash
# Start server and bankd
docker-compose up -d server bankd

# View logs
docker-compose logs -f

# Stop all services
docker-compose down
```

### All-in-One Mode

For testing purposes, you can run both server and bankd in a single container:

```bash
docker-compose --profile all-in-one up -d all-in-one
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Docker Host                                  │
├─────────────────────┬───────────────────────────────────────────┤
│  remsim-server      │              remsim-bankd                 │
│  (Port 9997, 9998)  │              (Port 9999)                  │
│                     │                    │                       │
│  - REST API (9997)  │                    │                       │
│  - RSPRO (9998)     │                    ▼                       │
│         ▲           │            ┌──────────────┐                │
│         │           │            │    pcscd     │                │
│         │           │            └──────────────┘                │
│         │           │                    │                       │
│         │           │                    ▼                       │
│         │           │            ┌──────────────┐                │
│         │           │            │  USB Device  │ ◄── Octosim    │
│         │           │            └──────────────┘                │
└─────────┼───────────┴────────────────────────────────────────────┘
          │
          ▼
    ┌───────────┐
    │  OpenWRT  │
    │  Client   │
    └───────────┘
```

## USB Device Access

### Option 1: Privileged Mode (Easiest)

```bash
docker run --privileged -v /dev/bus/usb:/dev/bus/usb osmo-remsim bankd
```

### Option 2: Specific Device Access

Find your USB device:
```bash
lsusb
# Example: Bus 001 Device 003: ID 1d50:4004 OpenMoko, Inc. SIMtrace 2
```

Run with specific device:
```bash
docker run --device=/dev/bus/usb/001/003 osmo-remsim bankd
```

### Option 3: Device Group Access

```bash
# Add udev rules for your reader (on host)
echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", ATTR{idProduct}=="4004", MODE="0666"' | \
  sudo tee /etc/udev/rules.d/99-simtrace.rules
sudo udevadm control --reload-rules

# Run container with USB group
docker run --group-add $(getent group plugdev | cut -d: -f3) \
  -v /dev/bus/usb:/dev/bus/usb \
  osmo-remsim bankd
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REMSIM_SERVER_HOST` | (required for bankd) | Server hostname/IP |
| `REMSIM_SERVER_PORT` | 9998 | Server RSPRO port |
| `REMSIM_BANK_ID` | 1 | Bank identifier |
| `REMSIM_NUM_SLOTS` | 8 | Number of SIM slots |
| `REMSIM_BIND_IP` | (all interfaces) | Bankd bind IP |
| `REMSIM_BIND_PORT` | 9999 | Bankd bind port |

### Slot Configuration

Create a `bankd_pcsc_slots.csv` file to map slot numbers to PC/SC reader names:

```csv
1,0,OctoSIM 8-Port SIM Bank 00 00
1,1,OctoSIM 8-Port SIM Bank 00 01
1,2,OctoSIM 8-Port SIM Bank 00 02
1,3,OctoSIM 8-Port SIM Bank 00 03
1,4,OctoSIM 8-Port SIM Bank 00 04
1,5,OctoSIM 8-Port SIM Bank 00 05
1,6,OctoSIM 8-Port SIM Bank 00 06
1,7,OctoSIM 8-Port SIM Bank 00 07
```

Mount this file:
```bash
docker run -v ./bankd_pcsc_slots.csv:/etc/osmocom/bankd_pcsc_slots.csv osmo-remsim bankd
```

### Finding Reader Names

List available PC/SC readers:
```bash
# Inside the container
docker exec remsim-bankd pcsc_scan -r

# Or using the list-readers command
docker run --privileged -v /dev/bus/usb:/dev/bus/usb osmo-remsim list-readers
```

## Exposed Ports

| Port | Service | Protocol | Description |
|------|---------|----------|-------------|
| 9997 | Server | HTTP | REST API for slot management |
| 9998 | Server | RSPRO | Server ↔ Bankd/Client communication |
| 9999 | Bankd | RSPRO | Bankd ↔ Client communication |

## Testing with OpenWRT Client

1. Start the server:
```bash
docker run -d --name remsim-server -p 9997:9997 -p 9998:9998 osmo-remsim server
```

2. Start the bankd with your Octosim reader:
```bash
docker run -d --name remsim-bankd \
  --privileged \
  -v /dev/bus/usb:/dev/bus/usb \
  -v ./bankd_pcsc_slots.csv:/etc/osmocom/bankd_pcsc_slots.csv \
  -e REMSIM_SERVER_HOST=<your-server-ip> \
  osmo-remsim bankd
```

3. On your OpenWRT device, configure the remsim client to connect to `<your-server-ip>:9998`.

4. Use the REST API to create slot mappings:
```bash
# List current mappings
curl http://localhost:9997/api/backend/slotmaps

# Create a mapping (client 0, slot 0 → bank 1, slot 0)
curl -X POST http://localhost:9997/api/backend/slotmaps \
  -H "Content-Type: application/json" \
  -d '{"client": {"client_id": 0, "slot_nr": 0}, "bank": {"bank_id": 1, "slot_nr": 0}}'
```

## Troubleshooting

### No PC/SC readers found

1. Check USB device visibility:
```bash
docker exec remsim-bankd lsusb
```

2. Check pcscd status:
```bash
docker exec remsim-bankd pgrep pcscd
```

3. Check PC/SC readers:
```bash
docker exec remsim-bankd pcsc_scan -r
```

### Connection refused to server

1. Verify server is running:
```bash
docker logs remsim-server
```

2. Check network connectivity:
```bash
docker exec remsim-bankd ping -c 1 remsim-server
```

3. Verify ports are exposed:
```bash
docker port remsim-server
```

### Bankd fails to start

1. Check required environment:
```bash
docker logs remsim-bankd
# Ensure REMSIM_SERVER_HOST is set
```

2. Verify slot configuration exists:
```bash
docker exec remsim-bankd cat /etc/osmocom/bankd_pcsc_slots.csv
```

## Building Custom Images

### Build Arguments

```bash
# Build with specific base image
docker build --build-arg BASE_IMAGE=debian:bullseye-slim -t osmo-remsim .
```

### Multi-Architecture Builds

```bash
# Build for ARM64 (e.g., for Raspberry Pi)
docker buildx build --platform linux/arm64 -t osmo-remsim:arm64 .
```

## Security Considerations

- **Privileged mode**: The bankd container requires privileged mode or specific device access for USB. Consider using specific device mounts instead of full privileged access in production.

- **Network isolation**: Consider using Docker networks to isolate the remsim services from untrusted networks.

- **Resource limits**: Add resource constraints for production deployments:
```yaml
services:
  server:
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
```

## See Also

- [osmo-remsim User Manual](https://downloads.osmocom.org/docs/latest/osmo-remsim-usermanual.pdf)
- [OpenWRT Integration Guide](doc/OPENWRT-INTEGRATION.md)
- [Build Documentation](BUILD.md)
