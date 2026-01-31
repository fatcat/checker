#!/usr/bin/env ruby
# frozen_string_literal: true

# Cleanup script to remove jitter data from non-ping measurements
# Jitter (IPDV) is only valid for ping tests with multiple packets

# Load just what we need
require 'sequel'

# Connect to database
DB = Sequel.sqlite('/home/mcnultyd/dev/checker/db/checker_development.sqlite3')

puts "Cleaning up jitter data from non-ping measurements..."
puts "=" * 60

# Get count of measurements with jitter for non-ping tests
affected_count = DB[:measurements]
  .where(Sequel.~(test_type: 'ping'))
  .where(Sequel.~(jitter_ms: nil))
  .count

puts "Found #{affected_count} non-ping measurements with jitter data"

if affected_count > 0
  # Set jitter_ms to NULL for all non-ping measurements
  updated = DB[:measurements]
    .where(Sequel.~(test_type: 'ping'))
    .where(Sequel.~(jitter_ms: nil))
    .update(jitter_ms: nil)

  puts "✓ Cleared jitter data from #{updated} measurements"
else
  puts "✓ No cleanup needed - database is already clean"
end

puts "=" * 60
puts "Cleanup complete!"
