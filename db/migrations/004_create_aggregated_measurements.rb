# frozen_string_literal: true

Sequel.migration do
  change do
    # 15-minute aggregates (for data 14-30 days old)
    create_table(:measurements_15min) do
      primary_key :id
      foreign_key :host_id, :hosts, null: false, on_delete: :cascade
      DateTime :period_start, null: false
      DateTime :period_end, null: false
      Integer :test_count, null: false, default: 0
      Integer :success_count, null: false, default: 0
      Float :avg_latency_ms
      Float :min_latency_ms
      Float :max_latency_ms
      Float :avg_jitter_ms
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :host_id
      index :period_start
      index [:host_id, :period_start]
    end

    # Hourly aggregates (for data 30+ days old)
    create_table(:measurements_hourly) do
      primary_key :id
      foreign_key :host_id, :hosts, null: false, on_delete: :cascade
      DateTime :period_start, null: false
      DateTime :period_end, null: false
      Integer :test_count, null: false, default: 0
      Integer :success_count, null: false, default: 0
      Float :avg_latency_ms
      Float :min_latency_ms
      Float :max_latency_ms
      Float :avg_jitter_ms
      DateTime :created_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index :host_id
      index :period_start
      index [:host_id, :period_start]
    end
  end
end
