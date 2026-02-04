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

### February 2025 - Rolling Window Statistics and Outlier Detection

Implemented rolling window averages for more stable statistics and automatic outlier detection with retesting to filter transient network issues.

#### Changes Made

**1. Fixed Jitter Chart Detection ([app/views/host_detail.erb](app/views/host_detail.erb))**
- Changed JavaScript to check for enabled jitter test instead of ping test
- Updated `hasJitterTest` logic to look for `test_type === 'jitter'`
- Fixed message: "Jitter tracking requires an enabled jitter test"
- Aligns with architecture where jitter is separate from ping

**2. Rolling Window Statistics ([app/routes/hosts.rb](app/routes/hosts.rb))**
- **Before**: Stats calculated from all measurements in selected time range (1h, 6h, 24h, etc.)
- **After**: Stats calculated from last 50 measurements per test type
- Each test type maintains independent rolling window:
  - Last 50 ping results → latency stats
  - Last 50 TCP results → latency stats
  - Last 50 HTTP results → latency stats
  - Last 50 DNS results → latency stats
  - Last 50 jitter results → jitter stats
- Aggregated statistics:
  - Avg/Min/Max Latency: From all latency-based test types combined
  - Avg Jitter: From jitter test type only
  - Uptime %: Success rate across all test types
  - Total Tests: Sum of measurements (up to 50 × number of enabled test types)
- Added `window_size` field to API response

**3. Frontend Statistics Display ([app/views/host_detail.erb](app/views/host_detail.erb))**
- Added "Statistics" header with description
- Added label: "Rolling average of last 50 measurements"
- Added CSS styling for stats header and description
- Charts still use time range selector (independent from stats)

**4. Outlier Detection with Automatic Retesting ([lib/checker/testers/base.rb](lib/checker/testers/base.rb))**

**Configuration ([config/application.rb](config/application.rb))**:
- `outlier_detection_enabled`: Enable/disable feature (default: `true`)
- `outlier_threshold_multiplier`: Result must be this many times worse (default: `10`)
- `outlier_min_threshold_ms`: Minimum difference in ms to qualify (default: `500`)

**Detection Logic**:
- Queries last 50 measurements for the specific test type
- Calculates baseline average
- Result is outlier if BOTH conditions met:
  - Current value > baseline × multiplier (default 10×)
  - Difference > minimum threshold (default 500ms)
- Requires at least 5 historical samples for baseline

**Retest Logic**:
- If outlier detected, immediately reruns the same test
- Compares retest result to original outlier
- **If retest confirms** (within 50% of original): Records original result (real issue)
- **If retest normal**: Records retest result (discards transient spike)
- If retest fails: Confirms original was real issue

**Logging**:
```
[OutlierDetection] Potential outlier detected for example.com (ping): latency=2000ms
[OutlierDetection] Retest shows normal result for example.com (ping). Using retest values.
```

**Example**:
- Baseline: 20ms average latency
- Test result: 2000ms → Outlier detected (100× worse, >500ms diff)
- Retest: 25ms → Discards outlier, records 25ms
- Retest: 1800ms → Confirms issue, records 2000ms

#### Architecture Design

**Per-Test-Type Rolling Windows**:
- Each test type tracks its own history independently
- Ensures equal representation regardless of test frequency
- Prevents fast-running tests from dominating statistics
- Jitter measurements already represent test results (avg of 5 pings per RFC 3393)

**Outlier Detection Approach**:
- Simple threshold-based (not statistical methods like z-score)
- Benefits:
  - Easy to understand and configure
  - Predictable behavior
  - Computationally lightweight
  - Appropriate for network monitoring (dramatic spikes are obvious)
- Executed in `record_result` before database insertion
- Uses existing `record_results: false` flag to prevent retest recording

#### Implementation Notes

**Rolling Window Statistics**:
- Stats now independent of time range selector
- Provides stable performance metrics
- Charts still use time range for historical analysis
- Window size (50) provides good balance of stability vs responsiveness

**Outlier Detection**:
- Only runs for successful tests (reachable=true)
- Only runs when recording results (not for validation tests)
- Creates new tester instance with `record_results: false` for retest
- No infinite loops due to flag isolation
- Minimal performance impact (single additional test when outlier detected)

#### Files Modified

1. `app/views/host_detail.erb` - Fixed jitter test detection, added stats header
2. `app/routes/hosts.rb` - Implemented per-test-type rolling window statistics
3. `lib/checker/testers/base.rb` - Added outlier detection and retest logic
4. `config/application.rb` - Added outlier detection configuration settings
5. `CLAUDE.md` - This entry

#### Benefits

**Rolling Window Statistics**:
- Consistent metrics regardless of time range selected
- Equal representation across all test types
- More stable averages (not affected by old data when switching ranges)
- Clear separation: stats for current state, charts for historical trends

**Outlier Detection**:
- Filters transient network glitches automatically
- Preserves real performance degradation events
- No false positives from isolated packet loss
- Transparent logging for troubleshooting
- Configurable thresholds for different use cases

### February 2025 - Code Review and Security Fixes

Comprehensive code review identified 23 issues across 6 severity categories. Fixed the 8 highest-priority issues.

#### Security Fixes (Critical)

**1. Command Injection in Ping/Jitter Testers**
- **Files:** [lib/checker/testers/ping.rb](lib/checker/testers/ping.rb), [lib/checker/testers/jitter.rb](lib/checker/testers/jitter.rb)
- **Problem:** Host addresses were interpolated directly into shell commands without escaping
- **Fix:** Added `Shellwords.shellescape` to sanitize addresses before command execution
```ruby
require 'shellwords'
safe_address = Shellwords.shellescape(address)
cmd = "ping -c #{count} -W #{timeout} -i 0.2 #{safe_address} 2>&1"
```

**2. Socket Leak in TCP Tester**
- **File:** [lib/checker/testers/tcp.rb](lib/checker/testers/tcp.rb)
- **Problem:** Socket not closed on timeout or exception paths
- **Fix:** Added `ensure` block to guarantee socket cleanup
```ruby
ensure
  socket&.close
end
```

#### Data Integrity Fix (Critical)

**3. Rakefile Rollback Bug**
- **File:** [Rakefile](Rakefile)
- **Problem:** `db:rollback` task called `Sequel::Migrator.run()` twice - once attempting to get version (but `run()` executes migrations, not returns version), potentially corrupting database
- **Fix:** Properly get current version using `applied_migrations` before calculating rollback target
```ruby
applied = Sequel::Migrator.migrator_class(migrations_path).new(db, migrations_path).applied_migrations
current_version = applied.map { |m| m.to_i }.max
target_version = [current_version - 1, 0].max
Sequel::Migrator.run(db, migrations_path, target: target_version)
```

#### Bug Fixes (High)

**4. Aggregator Missing test_type Grouping**
- **Files:** [lib/checker/aggregator.rb](lib/checker/aggregator.rb), [db/migrations/009_add_test_type_to_aggregates.rb](db/migrations/009_add_test_type_to_aggregates.rb)
- **Problem:** Aggregated measurements tables lacked `test_type` column, mixing statistics across different test types
- **Fix:**
  - Created migration 009 to add `test_type` to `measurements_15min` and `measurements_hourly` tables
  - Updated unique indexes to include `test_type`
  - Modified aggregator to group by `[test_type, period]` instead of just `period`
  - Backfilled existing data with 'ping' as default

**5. Race Condition in Scheduler**
- **File:** [lib/checker/scheduler.rb](lib/checker/scheduler.rb)
- **Problem:** Multiple workers could query and run the same due tests simultaneously
- **Fix:** Atomic claim pattern - update `next_test_at` with WHERE clause before running test
```ruby
claimed = Test.where(id: test.id)
  .where { Sequel.|({ next_test_at: nil }, Sequel.expr(next_test_at) <= now) }
  .update(next_test_at: next_time)
next if claimed.zero?  # Skip if another worker claimed it
```

**6. Duplicate Scheduler Queries**
- **File:** [lib/checker/scheduler.rb](lib/checker/scheduler.rb)
- **Problem:** Two separate queries for `next_test_at <= now` and `next_test_at: nil`
- **Fix:** Combined into single query using Sequel OR syntax
```ruby
.where { Sequel.|({ next_test_at: nil }, Sequel.expr(next_test_at) <= now) }
```

#### Code Quality Fixes

**7. Duplicated build_test_config Method**
- **Files:** [config/application.rb](config/application.rb), [app/routes/hosts.rb](app/routes/hosts.rb), [app/routes/tests.rb](app/routes/tests.rb), [lib/checker/scheduler.rb](lib/checker/scheduler.rb), [Rakefile](Rakefile)
- **Problem:** Same timeout configuration hash built in 4+ locations
- **Fix:** Centralized in `Configuration.test_config` method, all call sites updated

**8. Added RuboCop Configuration**
- **File:** [.rubocop.yml](.rubocop.yml)
- Added comprehensive RuboCop config with:
  - Ruby 3.3 target
  - Sensible metric limits (line length 120, method length 25)
  - Excluded migrations and vendor directories
  - Project-specific style preferences (single quotes, no trailing commas)

#### Files Modified/Created

**Created:**
1. `db/migrations/009_add_test_type_to_aggregates.rb`
2. `.rubocop.yml`

**Modified:**
1. `lib/checker/testers/ping.rb` - Command injection fix
2. `lib/checker/testers/jitter.rb` - Command injection fix
3. `lib/checker/testers/tcp.rb` - Socket leak fix
4. `lib/checker/aggregator.rb` - test_type grouping
5. `lib/checker/scheduler.rb` - Race condition fix, query consolidation
6. `config/application.rb` - Centralized test_config
7. `app/routes/hosts.rb` - Use Configuration.test_config
8. `app/routes/tests.rb` - Use Configuration.test_config
9. `Rakefile` - Rollback fix, use Configuration.test_config
10. `Gemfile` - Added rubocop gem (optional rubocop-sequel commented)

#### Test Coverage

All 73 tests passing after fixes.

#### Remaining Issues (Not Yet Fixed)

Prioritized list for future work:

**Medium Priority:**
- N+1 queries in host list (eager load tests)
- Constant reassignment warnings in testers
- Long methods in routes (extract to services)
- Magic numbers (extract to constants)
- Inconsistent error handling patterns

**Lower Priority:**
- Inconsistent private section placement
- Namespace organization (models in Checker module)
- No API rate limiting
- No pagination for measurements
- Missing database indexes on frequently queried columns
- No connection pooling configuration
- Inconsistent string quoting (mixed single/double)
- Loose gem version pinning

### February 2025 - Outlier Detection Improvements

Reviewed and improved the outlier detection feature with simplified, proportional logic.

#### Changes Made

**1. Simplified to Median-Based Proportional Detection**
- **File:** [lib/checker/testers/base.rb](lib/checker/testers/base.rb)
- Replaced mean-based calculation with **median** (more robust against existing outliers in baseline)
- Removed fixed minimum threshold (500ms) which was inappropriate for low-latency tests
- New logic: `outlier if value > median × multiplier` (single condition)
- Added `calculate_median` helper method

**2. Adjusted Default Threshold Multiplier**
- **File:** [config/application.rb](config/application.rb)
- Changed `outlier_threshold_multiplier` default from 10× to 5×
- Removed `outlier_min_threshold_ms` setting entirely

**3. Added Outlier Detection Settings to UI**
- **File:** [app/views/settings.erb](app/views/settings.erb)
- New "Outlier Detection" section in Settings page with:
  - Enable/disable checkbox (`outlier_detection_enabled`)
  - Threshold multiplier input (`outlier_threshold_multiplier`, default 5×)
- Explanatory info box describing median-based detection
- Removed minimum threshold field (no longer applicable)

**4. Added Comprehensive Test Coverage**
- **File:** [test/lib/testers/test_outlier_detection.rb](test/lib/testers/test_outlier_detection.rb) (new)
- 16 tests covering:
  - `calculate_median` helper (odd/even counts)
  - `is_outlier?` method with various edge cases
  - Test confirming median is used (not mean)
  - `retest_confirms_outlier?` method logic
  - Jitter test type handling
  - Settings enable/disable behavior
  - `record_results: false` flag preventing loops

#### Outlier Detection Logic

A result is flagged as a potential outlier when:
- Current value > baseline **median** × multiplier (default 5×)

**Why median instead of mean:**
- Median is robust against existing outliers in the baseline
- Mean can be skewed by a few high values, making detection unreliable

**Why no minimum threshold:**
- Fixed threshold (e.g., 500ms) was inappropriate for low-latency tests (ping, TCP)
- Proportional detection automatically scales to each test's typical values
- The retest mechanism handles false positives from measurement noise

Requires at least 5 historical samples to establish baseline. When flagged:
- Immediate retest with `record_results: false` (prevents recursion)
- If retest within 50% of original → confirms real issue → record original
- If retest much better → transient spike → record retest values

#### Files Modified/Created

**Created:**
1. `test/lib/testers/test_outlier_detection.rb` - 16 new tests

**Modified:**
1. `lib/checker/testers/base.rb` - Switched to median, removed min threshold, added calculate_median
2. `config/application.rb` - Changed default multiplier to 5, removed min_threshold setting
3. `app/views/settings.erb` - Updated UI, removed min threshold field

#### Test Coverage

Total tests now: 89 (73 existing + 16 new outlier detection tests)
