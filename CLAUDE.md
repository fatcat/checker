# Claude Code Context

## Project Overview

Network Checker is a self-hosted network monitoring application built with Ruby/Sinatra. It monitors host availability using multiple test types (ping, TCP, HTTP, DNS) and displays metrics via a web dashboard.

## Tech Stack

- **Framework**: Sinatra 4.x
- **Database**: SQLite3 with Sequel ORM
- **Server**: Puma
- **Scheduler**: rufus-scheduler for background tests
- **Frontend**: ERB templates with vanilla JS and Chart.js

## Key Directories

- `app/` - Sinatra application (routes, models, views)
- `bin/` - Executable helper scripts (console, setup, server, test)
- `lib/checker/testers/` - Test implementations (ping, tcp, http, dns)
- `lib/checker/scheduler.rb` - Background job scheduling
- `lib/tasks/` - Rake tasks
- `config/` - Application and database configuration
- `db/migrations/` - Sequel migrations
- `test/` - Minitest test suite (models, testers, integration)
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
# Initial setup (installs dependencies, creates database, runs migrations)
./bin/setup

# Start the server
./bin/server

# Or use individual commands
bundle install
bundle exec rake db:migrate
bundle exec puma config.ru
```

App runs on http://localhost:9292

**Helper Scripts:**
- `./bin/console` - Interactive console with app environment loaded
- `./bin/setup` - Initial project setup
- `./bin/server` - Start Puma server
- `./bin/test` - Run test suite

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

#### Remaining Work (Frontend)

**Frontend (3 tasks):**
- Update hosts.erb with multi-test form UI
- Update JavaScript for multiple tests & immediate validation
- Add CSS for test badges and validation results

#### Migration Notes

- Migration 007 creates tests table with composite index on (enabled, next_test_at) for scheduler performance
- Auto-creates ping test for all hosts
- UDP hosts converted to ping-only (logged during migration)
- All historical measurements preserved
- **Rollback is lossy** - only first test per host restored on rollback

### February 2025 - Ruby Conventions Refactoring

Refactored project structure to follow standard Ruby conventions and added comprehensive test suite.

#### Changes Made

**Project Structure:**
- Added `.ruby-version` file (3.3.0) for rbenv/rvm consistency
- Created `bin/` directory with executable helper scripts:
  - `bin/console` - Interactive IRB console with app environment
  - `bin/setup` - Initial project setup automation
  - `bin/server` - Puma server wrapper
  - `bin/test` - Test suite runner
- Added `lib/checker/version.rb` for version management (0.1.0)
- Created `lib/tasks/` directory for Rake tasks
- Removed one-time jitter cleanup script (no longer needed)

**Testing Framework:**
- Switched from RSpec (not implemented) to Minitest
- Created comprehensive test suite with 63 tests:
  - `test/models/` - Model tests (Host, Test, Measurement)
  - `test/lib/testers/` - Tester tests (Ping, TCP, HTTP, DNS)
  - `test/lib/` - Scheduler tests
  - `test/integration/` - API integration tests
- Added `test/test_helper.rb` with shared utilities and test database setup
- Configured Rake test task as default task

**Dependencies:**
- Updated `Gemfile` to include:
  - `rake ~> 13.0`
  - `minitest ~> 5.0`
  - `minitest-reporters ~> 1.6`
  - Kept `rack-test` for integration testing
- Updated `.gitignore` for test artifacts

**Documentation:**
- Updated `README.md` to reflect new structure and test framework
- Fixed repository URL from `network-checker` to `checker`
- Removed UDP references throughout documentation

#### Test Coverage

All tests passing (63 total):
- 16 Host model tests - validation, associations, status methods
- 15 Test model tests - validation, status calculation, degraded thresholds
- 7 Measurement model tests - creation, queries, aggregation
- 5 Scheduler tests - initialization, test execution, timing
- 12 Tester tests - ping (with jitter), TCP, HTTP, DNS functionality
- 8 API integration tests - health check, CRUD operations, validation

#### Implementation Notes

- Test database uses `checker_test.sqlite3` in development
- All tests use `Minitest::Test` base class with shared `TestHelpers` module
- Tests set `ENV['DISABLE_SCHEDULER'] = 'true'` to prevent background jobs
- Each test truncates tables in setup for isolation
- Minitest reporters provide RSpec-style output formatting

### February 2025 - Settings and Data Retention Improvements

Enhanced settings page and implemented data retention policies for long-term database management.

#### Changes Made

**Settings Page:**
- Added DNS timeout configuration (default 5 seconds)
- Fixed TCP timeout label (removed UDP reference)
- Added data lifecycle documentation to Settings UI showing retention policies and database size estimates

**Data Retention:**
- Implemented 1-year hard-coded retention for hourly aggregates
- Added cleanup routine in aggregator to delete hourly data older than 365 days
- Database steady-state size: approximately 50 MB for 10 tests running continuously

**Data Lifecycle:**
1. Raw measurements → kept for configurable days (default 14), then aggregated to 15-minute intervals
2. 15-minute aggregates → kept for configurable days (default 30), then aggregated to hourly intervals
3. Hourly aggregates → kept for maximum 1 year (365 days hard-coded)

**Files Modified:**
- `config/application.rb` - Added `dns_timeout_seconds` to DEFAULT_SETTINGS
- `app/views/settings.erb` - Added DNS timeout field, retention info box with lifecycle documentation and styling
- `lib/checker/aggregator.rb` - Added `cleanup_hourly_data` method with 365-day retention
- `README.md` - Updated Application Settings table with complete retention information and size estimates

### February 2025 - Separate Jitter from Latency Ping Testing

Refactored ping testing architecture to separate jitter calculation from latency measurement, providing clearer distinction and independent control.

#### User Requirements

- Add "perform jitter calculation for this host" checkbox at host level (under address field)
- Change ping test to single-ping latency measurement only
- Create separate jitter test with 5 pings and 0.2s interval for IPDV calculation
- Jitter test uses same timeout as ping latency test
- Jitter test failures visible in dashboard and host config UI (same as latency tests)
- Clear distinction between jitter calculation and latency tests in UI

#### Architecture Design

**Hybrid Approach:**
- Added `jitter_enabled` boolean to hosts table (host-level setting)
- When jitter_enabled=true, automatically create test with test_type='jitter'
- When jitter_enabled=false, automatically delete jitter test
- Modified ping tester to do single ping (latency only, no jitter)
- Created new jitter tester to do 5 pings (IPDV jitter calculation)

**Benefits:**
- Clean UI placement (checkbox under host address as requested)
- Backend treats jitter as a test (integrates with existing scheduler/frontend)
- Frontend test badges automatically include jitter (no special handling)
- API handles jitter_enabled on host, automatically manages jitter test
- Jitter failures visible same as other test failures (status badges, error messages)

#### Changes Made

**Database:**
- Migration 008: Added `jitter_enabled` column to hosts table (default: false, null: false)
- Test model: Added 'jitter' to VALID_TEST_TYPES and DEGRADED_THRESHOLDS
- Host model: Callbacks to automatically create/delete jitter test when jitter_enabled toggled

**Testers:**
- Modified ping tester ([lib/checker/testers/ping.rb](lib/checker/testers/ping.rb)): Single ping (count=1), latency only, removed jitter calculation
- Created jitter tester ([lib/checker/testers/jitter.rb](lib/checker/testers/jitter.rb)): 5 pings with 0.2s interval, IPDV calculation, same timeout as ping
- Updated [lib/checker/testers.rb](lib/checker/testers.rb): Registered jitter tester

**Models:**
- [app/models/host.rb](app/models/host.rb):
  - Added jitter_enabled validation (requires valid address)
  - Added before_update and after_create callbacks to manage jitter test
  - Updated to_api_v2 to include jitter_enabled field
  - Updated status_summary to get jitter from jitter test (not ping)
  - Added private manage_jitter_test method
- [app/models/test.rb](app/models/test.rb):
  - Added 'jitter' to VALID_TEST_TYPES
  - Added 'jitter' to DEGRADED_THRESHOLDS (1000ms, same as ping)

**API:**
- [app/routes/hosts.rb](app/routes/hosts.rb):
  - Added `jitter_enabled` field to POST and PUT endpoints
  - Automatic jitter test creation/deletion via host callbacks
  - Jitter test visible in validation results and test status arrays

**Frontend:**
- [app/views/hosts.erb](app/views/hosts.erb):
  - Added "Perform jitter calculation for this host" checkbox under address field
  - Renamed "Test Configuration" to "Latency Test Configuration"
  - Updated ping test label to "Ping (ICMP) Latency"
  - Updated form hints to clarify jitter vs latency distinction
  - JavaScript updates:
    - showAddForm() resets jitter checkbox to false
    - editHost() loads jitter_enabled from host data
    - saveHost() includes jitter_enabled in payload
  - Jitter test appears in test status badges automatically

**Tests:**
- [test/lib/testers/test_ping.rb](test/lib/testers/test_ping.rb): Updated expectations to single ping, removed jitter test
- [test/lib/testers/test_jitter.rb](test/lib/testers/test_jitter.rb) (new): 3 tests for jitter calculation, insufficient pings, timeout
- [test/models/test_host.rb](test/models/test_host.rb): Added 3 tests for jitter_enabled validation and callbacks
- [test/lib/test_scheduler.rb](test/lib/test_scheduler.rb): Updated test_run_test_for_host to be flexible with test count
- [test/integration/test_api.rb](test/integration/test_api.rb): Fixed API test expectations (JSON structure, status codes)

**Documentation:**
- [README.md](README.md):
  - Updated "Multiple Test Types" section to show Ping as single ICMP request and Jitter as optional
  - Updated "Ping Count" setting description to clarify it's for jitter calculation
  - Updated "Adding Hosts" section to include jitter checkbox and latency test configuration
- [CLAUDE.md](CLAUDE.md): Added this session entry

#### Test Coverage

All tests passing (73 total):
- 19 Host model tests (added 3 jitter-related)
- 18 Test model tests
- 9 Measurement model tests
- 5 Scheduler tests (updated for flexibility)
- 15 Tester tests (3 ping updated, 3 jitter new, 3 TCP, 3 HTTP, 3 DNS)
- 8 API integration tests (fixed)

#### Implementation Notes

- Ping latency is now from single ping (faster, less network traffic)
- Jitter is measured using 5 pings with 0.2s interval (IPDV per RFC 3393)
- Jitter test is optional per host (not all hosts need jitter monitoring)
- Same degraded threshold for jitter as ping (1000ms)
- Jitter test uses same randomness_percent as other tests for scheduling variance
- Test database migration required (RACK_ENV=test bundle exec rake db:migrate)
- Migration 008 default jitter_enabled=false (existing hosts won't have jitter)

#### Files Modified/Created

**Created:**
1. `db/migrations/008_add_jitter_to_hosts.rb`
2. `lib/checker/testers/jitter.rb`
3. `test/lib/testers/test_jitter.rb`

**Modified:**
1. `app/models/host.rb` - jitter_enabled field, callbacks, API, status_summary
2. `app/models/test.rb` - Added 'jitter' to VALID_TEST_TYPES and DEGRADED_THRESHOLDS
3. `lib/checker/testers/ping.rb` - Single ping, removed jitter calculation
4. `lib/checker/testers.rb` - Registered jitter tester
5. `app/routes/hosts.rb` - Added jitter_enabled to POST/PUT
6. `app/views/hosts.erb` - Jitter checkbox, section rename, JavaScript
7. `test/lib/testers/test_ping.rb` - Updated expectations
8. `test/models/test_host.rb` - Added jitter tests
9. `test/lib/test_scheduler.rb` - Flexible test count
10. `test/integration/test_api.rb` - Fixed expectations
11. `README.md` - Updated documentation
12. `CLAUDE.md` - This entry
