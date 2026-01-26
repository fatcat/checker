# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:settings) do
      primary_key :id
      String :key, null: false, unique: true
      String :value, text: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :key, unique: true
    end
  end
end
