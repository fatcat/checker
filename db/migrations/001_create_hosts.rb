# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:hosts) do
      primary_key :id
      String :name, null: false
      String :address, null: false
      Integer :port
      String :test_type, null: false, default: 'ping' # ping, tcp, udp, http
      TrueClass :enabled, null: false, default: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :enabled
      index :test_type
    end
  end
end
