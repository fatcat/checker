# Network Checker - Dockerfile
# Multi-stage build for smaller image size

# Build stage
FROM ruby:3.3-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    sqlite-dev

WORKDIR /app

# Copy dependency files
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4

# Runtime stage
FROM ruby:3.3-alpine

# Install runtime dependencies
# - sqlite: database
# - iputils: ping command for ICMP tests
# - bind-tools: dig/nslookup for DNS tests
# - tzdata: timezone data
RUN apk add --no-cache \
    sqlite-libs \
    iputils \
    bind-tools \
    tzdata

# Create non-root user for security
RUN addgroup -g 1000 checker && \
    adduser -u 1000 -G checker -s /bin/sh -D checker

WORKDIR /app

# Copy application code
COPY --chown=checker:checker . .

# Copy gems from builder
COPY --from=builder --chown=checker:checker /app/vendor/bundle ./vendor/bundle
COPY --from=builder --chown=checker:checker /app/.bundle ./.bundle

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

# Expose port
EXPOSE 9292

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://localhost:9292/health || exit 1

# Start the application
CMD ["bundle", "exec", "puma", "-C", "-", "-b", "tcp://0.0.0.0:9292", "config.ru"]
