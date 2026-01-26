# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:measurements) do
      primary_key :id
      foreign_key :host_id, :hosts, null: false, on_delete: :cascade
      String :test_type, null: false
      TrueClass :reachable, null: false, default: false
      Float :latency_ms
      Float :jitter_ms
      Integer :http_status
      String :error_message, text: true
      DateTime :tested_at, null: false, index: true
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :host_id
      index [:host_id, :tested_at]
    end
  end
end
