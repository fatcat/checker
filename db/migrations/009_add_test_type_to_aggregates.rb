# frozen_string_literal: true

# Migration 009: Add test_type to aggregated measurements tables
#
# With multi-test architecture (migration 007), each host can have multiple
# test types running simultaneously. The aggregated measurements tables need
# test_type to properly separate statistics per test type.
#
# This migration adds test_type columns and updates indexes for proper grouping.

Sequel.migration do
  up do
    puts "=== Migration 009: Adding test_type to aggregated measurements ==="

    # Add test_type to measurements_15min
    puts "Adding test_type to measurements_15min..."
    alter_table :measurements_15min do
      add_column :test_type, String, null: true
      drop_index [:host_id, :period_start]
      add_index [:host_id, :test_type, :period_start], unique: true
    end

    # Backfill test_type for existing 15min records
    # Default to 'ping' for historical data (most common test type)
    from(:measurements_15min).update(test_type: 'ping')

    # Now make it non-null
    alter_table :measurements_15min do
      set_column_not_null :test_type
    end

    # Add test_type to measurements_hourly
    puts "Adding test_type to measurements_hourly..."
    alter_table :measurements_hourly do
      add_column :test_type, String, null: true
      drop_index [:host_id, :period_start]
      add_index [:host_id, :test_type, :period_start], unique: true
    end

    # Backfill test_type for existing hourly records
    from(:measurements_hourly).update(test_type: 'ping')

    # Now make it non-null
    alter_table :measurements_hourly do
      set_column_not_null :test_type
    end

    puts "=== Migration 009 complete! ==="
  end

  down do
    puts "=== Rolling back Migration 009 ==="

    alter_table :measurements_15min do
      drop_index [:host_id, :test_type, :period_start]
      drop_column :test_type
      add_index [:host_id, :period_start]
    end

    alter_table :measurements_hourly do
      drop_index [:host_id, :test_type, :period_start]
      drop_column :test_type
      add_index [:host_id, :period_start]
    end

    puts "=== Rollback complete ==="
  end
end
