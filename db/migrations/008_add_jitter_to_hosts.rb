# frozen_string_literal: true

Sequel.migration do
  up do
    alter_table(:hosts) do
      add_column :jitter_enabled, TrueClass, default: false, null: false
    end

    # Add 'jitter' to valid test types
    # (No database constraint currently enforces VALID_TEST_TYPES, it's only in model)
  end

  down do
    # Clean up any jitter tests before dropping column
    DB[:tests].where(test_type: 'jitter').delete

    alter_table(:hosts) do
      drop_column :jitter_enabled
    end
  end
end
