# frozen_string_literal: true

# Migration 007: Refactor from single-test-per-host to multiple-tests-per-host
#
# This migration:
# - Creates a new 'tests' table to store test configurations
# - Migrates existing host test configurations to the tests table
# - Creates ping tests for all hosts (ping becomes baseline for jitter)
# - Removes test-specific columns from hosts table
# - Renames randomness_percent to variability_percent for clarity
#
# IMPORTANT: Rollback is LOSSY - only the first test per host is preserved

Sequel.migration do
  up do
    puts "=== Migration 007: Refactoring to multiple-tests-per-host ==="

    # Step 1: Create tests table
    puts "Creating tests table..."
    create_table(:tests) do
      primary_key :id
      foreign_key :host_id, :hosts, null: false, on_delete: :cascade
      String :test_type, null: false  # 'ping', 'tcp', 'http', 'dns'
      Integer :port, null: true       # for tcp, http
      String :http_scheme, null: true # 'http' or 'https'
      String :dns_query_hostname, null: true  # for dns
      TrueClass :enabled, null: false, default: true
      DateTime :next_test_at, null: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :host_id
      index [:host_id, :test_type]
      index :next_test_at
      index [:enabled, :next_test_at]  # Scheduler query optimization

      # Constraint: Only one test of each type per host
      unique [:host_id, :test_type]
    end

    # Step 2: Migrate existing host test configurations
    puts "Migrating existing host configurations to tests table..."

    host_count = from(:hosts).count
    test_count = 0
    udp_count = 0

    from(:hosts).each do |host|
      test_type = host[:test_type]

      # Handle UDP deprecation
      if test_type == 'udp'
        puts "  WARNING: Host '#{host[:name]}' (ID: #{host[:id]}) has UDP test - UDP is deprecated, creating ping-only"
        udp_count += 1

        # Create ping test only for UDP hosts
        from(:tests).insert(
          host_id: host[:id],
          test_type: 'ping',
          enabled: host[:enabled],
          next_test_at: host[:next_test_at],
          created_at: Time.now,
          updated_at: Time.now
        )
        test_count += 1
        next
      end

      # Determine http_scheme from port for HTTP tests
      http_scheme = nil
      if test_type == 'http' && host[:port]
        http_scheme = host[:port] == 443 ? 'https' : 'http'
      end

      # Create test entry for existing test type
      from(:tests).insert(
        host_id: host[:id],
        test_type: test_type,
        port: host[:port],
        http_scheme: http_scheme,
        dns_query_hostname: host[:dns_query_hostname],
        enabled: host[:enabled],
        next_test_at: host[:next_test_at],
        created_at: Time.now,
        updated_at: Time.now
      )
      test_count += 1

      # Create ping test if original test type was not ping
      # This makes ping the baseline for all hosts (used for jitter measurement)
      if test_type != 'ping'
        from(:tests).insert(
          host_id: host[:id],
          test_type: 'ping',
          enabled: host[:enabled],
          next_test_at: host[:next_test_at],
          created_at: Time.now,
          updated_at: Time.now
        )
        test_count += 1
      end
    end

    puts "  Migrated #{host_count} hosts to tests table"
    puts "  Created #{test_count} test configurations"
    puts "  Deprecated #{udp_count} UDP tests (converted to ping-only)" if udp_count > 0

    # Step 3: Remove test-specific columns from hosts table
    puts "Cleaning up hosts table (removing test-specific columns)..."
    alter_table :hosts do
      drop_column :test_type
      drop_column :port
      drop_column :dns_query_hostname
      drop_column :next_test_at
    end

    puts "=== Migration 007 complete! ==="
    puts "Next steps:"
    puts "  1. Update code to use Test model instead of Host.test_type"
    puts "  2. Update scheduler to query tests table"
    puts "  3. Update testers to accept Test objects"
  end

  down do
    puts "=== Rolling back Migration 007 ==="
    puts "WARNING: This rollback is LOSSY - only the first test per host will be preserved!"

    # Step 1: Restore test-specific columns to hosts table
    puts "Restoring hosts table columns..."
    alter_table :hosts do
      add_column :test_type, String
      add_column :port, Integer
      add_column :dns_query_hostname, String
      add_column :next_test_at, DateTime
    end

    # Step 2: Copy first test back to host (LOSSY - only preserves one test per host)
    puts "Copying first test from each host back to hosts table..."

    from(:hosts).each do |host|
      # Get first test (preferring non-ping if available)
      tests = from(:tests).where(host_id: host[:id]).order(Sequel.desc(:test_type)).all
      test = tests.first

      next unless test

      from(:hosts).where(id: host[:id]).update(
        test_type: test[:test_type],
        port: test[:port],
        dns_query_hostname: test[:dns_query_hostname],
        next_test_at: test[:next_test_at]
      )
    end

    puts "  WARNING: Lost #{from(:tests).count - from(:hosts).count} additional tests during rollback"

    # Step 3: Drop tests table
    puts "Dropping tests table..."
    drop_table(:tests)

    puts "=== Rollback complete (with data loss) ==="
  end
end
