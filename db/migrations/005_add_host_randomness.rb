# frozen_string_literal: true

Sequel.migration do
  change do
    alter_table :hosts do
      add_column :randomness_percent, Integer, default: 0, null: false
      add_column :next_test_at, DateTime, null: true
    end
  end
end
