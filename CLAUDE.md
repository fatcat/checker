# Claude Code Context

## Project Overview

Network Checker is a self-hosted network monitoring application built with Ruby/Sinatra. It monitors host availability using multiple test types (ping, TCP, UDP, HTTP, DNS) and displays metrics via a web dashboard.

## Tech Stack

- **Framework**: Sinatra 4.x
- **Database**: SQLite3 with Sequel ORM
- **Server**: Puma
- **Scheduler**: rufus-scheduler for background tests
- **Frontend**: ERB templates with vanilla JS and Chart.js

## Key Directories

- `app/` - Sinatra application (routes, models, views)
- `lib/checker/testers/` - Test implementations (ping, tcp, udp, http, dns)
- `lib/checker/scheduler.rb` - Background job scheduling
- `config/` - Application and database configuration
- `db/migrations/` - Sequel migrations
- `themes/` - YAML theme definitions
- `public/` - Static assets (CSS, JS)

## Docker Deployment

The app uses a multi-stage Dockerfile with `ruby:3.3-slim` (Debian-based).

### Important Docker Notes

- Uses Debian slim instead of Alpine to avoid musl/glibc compatibility issues with native gems (sqlite3)
- Requires `NET_RAW` capability for ICMP ping tests
- Data persisted in `/data` volume (database + logs)
- Runs as non-root `checker` user (UID 1000)

### Common Commands

```bash
# Build and run
docker-compose build --no-cache && docker-compose up -d

# View logs
docker-compose logs -f checker

# Full rebuild (clear cache/volumes)
docker-compose down -v --rmi all && docker-compose up -d --build
```

## Local Development

```bash
bundle install
bundle exec rake db:migrate
bundle exec puma config.ru
```

App runs on http://localhost:9292

## API Endpoints

- `GET /health` - Health check
- `GET/POST/PUT/DELETE /api/hosts` - Host management
- `GET /api/measurements/*` - Measurement data
- `POST /api/tests/run/:id` - Trigger manual test
- `GET/PUT /api/settings` - App settings

## Session History

### January 2025 - Docker Deployment Fixes

Fixed several issues deploying to Docker:

1. **Missing .bundle directory** - Changed from copying `.bundle` from builder stage to running `bundle config` in runtime stage as the checker user

2. **sqlite3 native gem loading error** - Alpine's musl libc was incompatible with precompiled sqlite3 gems. Switched from `ruby:3.3-alpine` to `ruby:3.3-slim` (Debian-based) which uses glibc

3. **Bundle config ownership** - Moved `bundle config` commands to run after `USER checker` to ensure correct file ownership
