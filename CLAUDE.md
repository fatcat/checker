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

### January 2025 - Multi-Test Architecture Refactoring

**Status: Backend Complete (67%), Frontend & Testing Pending (33%)**

Refactored from single-test-per-host to multiple-concurrent-tests-per-host architecture. Each host can now run ping, TCP, HTTP, and DNS tests simultaneously.

#### Completed Work

**Database & Models:**
- Migration 007 (`db/migrations/007_refactor_to_multiple_tests.rb`) - Creates tests table, migrates data, handles UDP deprecation
- New Test model (`app/models/test.rb`) - Validation, status tracking (success/failure/never), API serialization
- Updated Host model (`app/models/host.rb`) - Removed test-specific fields, added tests association, v2 API support
- Updated Measurement model (`app/models/measurement.rb`) - Queries work with Test table

**Scheduler & Testers:**
- Scheduler (`lib/checker/scheduler.rb`) - Queries Test table, runs multiple tests per host independently
- Testers module (`lib/checker/testers.rb`) - Accepts Test objects instead of Host
- Base tester (`lib/checker/testers/base.rb`) - Updated interface
- HTTP tester (`lib/checker/testers/http.rb`) - Uses test.http_scheme field
- DNS tester (`lib/checker/testers/dns.rb`) - Uses test.dns_query_hostname
- **Removed** UDP tester - No reliable way to test generic UDP services
- **Jitter** - Only ping tests calculate jitter (IPDV), removed from TCP/HTTP/DNS

**API v2:**
- New v2 routes (`app/routes/v2/hosts.rb`) with:
  - Nested tests in responses
  - `validate_immediately` flag for immediate test execution on save
  - Automatic ping test creation for all hosts
  - Full CRUD operations
- v1 API deprecation headers added (6-month sunset)
- Main app (`app/app.rb`) - Loads v2 routes, deprecation helper

#### Key Design Decisions

1. **Tests table** - Each test has own next_test_at for per-test scheduling
2. **Ping always required** - Application-layer enforcement (frontend + API validation)
3. **HTTP scheme** - Separate http_scheme field ('http'/'https') removes port ambiguity
4. **Jitter** - Only ping tests (5-ping IPDV), removed from other protocols
5. **Measurements** - Table unchanged, still uses host_id + test_type

#### Remaining Work (Frontend & Testing)

**Frontend (3 tasks):**
- Update hosts.erb with multi-test form UI
- Update JavaScript for multiple tests & immediate validation
- Add CSS for test badges and validation results

**Testing (4 tasks):**
- Test migration with sample data
- Test scheduler functionality
- Test API v2 endpoints
- Test frontend UI flows

#### Migration Notes

- Migration 007 creates tests table with composite index on (enabled, next_test_at) for scheduler performance
- Auto-creates ping test for all hosts
- UDP hosts converted to ping-only (logged during migration)
- All historical measurements preserved
- **Rollback is lossy** - only first test per host restored on rollback
