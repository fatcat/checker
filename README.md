# Network Checker

A lightweight, self-hosted network monitoring application for tracking the availability and performance of hosts across your infrastructure.

## Features

- **Multiple Test Types**
  - **Ping (ICMP)** - Traditional ping with latency and jitter measurements
  - **TCP** - Port connectivity checks with response time
  - **UDP** - UDP port reachability testing
  - **HTTP/HTTPS** - Web endpoint monitoring with status code validation
  - **DNS** - DNS resolution testing with custom query support

- **Performance Metrics**
  - Latency tracking (min, max, average)
  - Jitter calculation using IPDV (Inter-Packet Delay Variation) per RFC 3393
  - Uptime percentage calculations
  - Historical data with configurable retention

- **Dashboard**
  - Real-time host status overview
  - Interactive latency and jitter charts (per host and grouped by test type)
  - Reachability heatmaps
  - Configurable time ranges (1 hour to 30 days)
  - Custom date range selection

- **Customization**
  - 12 built-in themes (6 dark, 6 light)
  - Configurable test intervals
  - Adjustable data retention periods
  - Per-host enable/disable controls

## Quick Start

### Docker (Recommended)

```bash
# Clone the repository
git clone https://github.com/fatcat/network-checker.git
cd network-checker

# Start with Docker Compose
docker compose up -d

# View logs
docker compose logs -f
```

The application will be available at `http://localhost:9292`

### Docker Run (Alternative)

```bash
# Build the image
docker build -t network-checker .

# Run the container
docker run -d \
  --name network-checker \
  --cap-add NET_RAW \
  -p 9292:9292 \
  -v checker-data:/data \
  network-checker
```

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RACK_ENV` | `production` | Application environment |
| `DATABASE_PATH` | `/data/db/checker.sqlite3` | SQLite database location |
| `LOG_DIR` | `/data/log` | Log file directory |
| `TZ` | `UTC` | Container timezone |
| `DISABLE_SCHEDULER` | (unset) | Set to disable automatic testing |
| `SKIP_MIGRATIONS` | (unset) | Set to skip database migrations |

### Application Settings

Settings can be configured through the web UI at `/settings`:

| Setting | Default | Description |
|---------|---------|-------------|
| Test Interval | 300s (5 min) | Time between automated tests |
| Raw Data Retention | 14 days | How long to keep individual measurements |
| HTTP Timeout | 10s | Timeout for HTTP/HTTPS tests |
| TCP Timeout | 5s | Timeout for TCP connection tests |
| Ping Count | 5 | Number of pings per test (for jitter calculation) |
| Ping Timeout | 5s | Timeout per ping packet |
| Theme | dark-default | UI color scheme |

## Adding Hosts

1. Navigate to **Hosts** in the navigation bar
2. Click **Add Host**
3. Fill in the host details:
   - **Name**: Display name for the host
   - **Address**: IP address or hostname
   - **Port**: (Optional) Port number for TCP/UDP/HTTP tests
   - **Test Type**: Select from ping, tcp, udp, http, or dns
   - **DNS Query Hostname**: (DNS only) Hostname to resolve
4. Click **Save**

## Architecture

```
network-checker/
├── app/
│   ├── models/          # Sequel ORM models
│   ├── routes/          # API endpoints
│   └── views/           # ERB templates
├── config/
│   ├── application.rb   # App configuration
│   └── database.rb      # Database setup
├── db/
│   └── migrations/      # Database migrations
├── lib/checker/
│   ├── testers/         # Test type implementations
│   ├── aggregator.rb    # Data aggregation
│   ├── logger.rb        # Rotating log handler
│   ├── scheduler.rb     # Background test scheduler
│   └── theme_loader.rb  # Theme management
├── public/              # Static assets (CSS, JS)
├── themes/              # Theme definitions (YAML)
├── config.ru            # Rack configuration
├── Dockerfile
└── docker-compose.yaml
```

## API Endpoints

### Hosts
- `GET /api/hosts` - List all hosts
- `GET /api/hosts/:id` - Get host details
- `POST /api/hosts` - Create a new host
- `PUT /api/hosts/:id` - Update a host
- `DELETE /api/hosts/:id` - Delete a host
- `GET /api/hosts/status` - Get current status of all hosts

### Measurements
- `GET /api/measurements/host/:id` - Get measurements for a host
- `GET /api/measurements/latency` - Get latency series for all hosts
- `GET /api/measurements/latency/by-type` - Get latency grouped by test type
- `GET /api/measurements/jitter` - Get jitter series for all hosts

### Tests
- `POST /api/tests/run/:id` - Run an immediate test for a host
- `POST /api/tests/run-all` - Run tests for all enabled hosts

### Settings
- `GET /api/settings` - Get all settings
- `PUT /api/settings` - Update settings

### System
- `GET /health` - Health check endpoint

## Data Persistence

When running with Docker, all data is stored in the `/data` volume:

- `/data/db/checker.sqlite3` - SQLite database with hosts, measurements, and settings
- `/data/log/checker.log.*` - Rotating application logs

To backup your data:

```bash
# Stop the container
docker compose stop

# Copy the data volume
docker run --rm -v checker-data:/data -v $(pwd):/backup alpine \
  tar czf /backup/checker-backup.tar.gz /data

# Restart
docker compose start
```

## Development

### Local Setup

```bash
# Install dependencies
bundle install

# Run migrations
bundle exec rake db:migrate

# Start the server
bundle exec puma config.ru
```

### Running Tests

```bash
bundle exec rspec
```

## Themes

Available themes:
- **Dark**: default, nord, dracula, monokai, solarized, gruvbox
- **Light**: default, nord, solarized, github, gruvbox, catppuccin

Themes can be changed in **Settings** and take effect immediately.

## Requirements

- Docker 20.10+ and Docker Compose v2 (for containerized deployment)
- Ruby 3.0+ (for local development)
- SQLite 3

## License

MIT License
