# Network Checker - Dockerfile
# Multi-stage build for smaller image size

# Build stage
FROM ruby:3.3-slim AS builder

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy dependency files
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle config set --local path 'vendor/bundle' && \
    bundle install --jobs 4

# Runtime stage
FROM ruby:3.3-slim

# Install runtime dependencies
# - libsqlite3-0: database
# - iputils-ping: ping command for ICMP tests
# - dnsutils: dig/nslookup for DNS tests
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-0 \
    iputils-ping \
    dnsutils \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for security
RUN groupadd -g 1000 checker && \
    useradd -u 1000 -g checker -s /bin/sh -m checker

WORKDIR /app

# Copy application code
COPY --chown=checker:checker . .

# Copy gems from builder
COPY --from=builder --chown=checker:checker /app/vendor/bundle ./vendor/bundle

# Create directories for persistent data
RUN mkdir -p /data/db /data/log && \
    chown -R checker:checker /data /app

# Environment variables
ENV RACK_ENV=production \
    DATABASE_PATH=/data/db/checker.sqlite3 \
    LOG_DIR=/data/log \
    PORT=9292

# Switch to non-root user
USER checker

# Configure bundler for deployment (run as checker user)
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle config set --local path 'vendor/bundle'

# Expose port
EXPOSE 9292

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:9292/health || exit 1

# Start the application
CMD ["bundle", "exec", "puma", "-C", "-", "-b", "tcp://0.0.0.0:9292", "config.ru"]
