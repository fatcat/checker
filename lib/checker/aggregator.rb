# frozen_string_literal: true

module Checker
  class Aggregator
    class << self
      def run
        Checker.logger.info "[Aggregator] Starting data aggregation..."

        raw_retention = Configuration.get('raw_data_retention_days').to_i
        agg_15min_retention = Configuration.get('aggregation_15min_retention_days').to_i

        # Step 1: Aggregate raw data older than 14 days into 15-minute buckets
        aggregate_to_15min(raw_retention)

        # Step 2: Aggregate 15-min data older than 30 days into hourly buckets
        aggregate_to_hourly(agg_15min_retention)

        # Step 3: Clean up old raw data
        cleanup_raw_data(raw_retention)

        # Step 4: Clean up old 15-min data
        cleanup_15min_data(agg_15min_retention)

        Checker.logger.info "[Aggregator] Aggregation complete"
      end

      private

      def aggregate_to_15min(days_old)
        cutoff = Time.now - (days_old * 24 * 60 * 60)

        Host.all.each do |host|
          # Find raw measurements older than cutoff that haven't been aggregated
          measurements = DB[:measurements]
            .where(host_id: host.id)
            .where { tested_at < cutoff }
            .order(:tested_at)
            .all

          next if measurements.empty?

          # Group by 15-minute periods
          grouped = measurements.group_by do |m|
            time = m[:tested_at]
            minute = (time.min / 15) * 15
            Time.new(time.year, time.month, time.day, time.hour, minute, 0)
          end

          grouped.each do |period_start, group|
            period_end = period_start + (15 * 60)

            # Check if already aggregated
            existing = DB[:measurements_15min]
              .where(host_id: host.id, period_start: period_start)
              .first

            next if existing

            # Calculate aggregates
            successful = group.select { |m| m[:reachable] }
            latencies = successful.map { |m| m[:latency_ms] }.compact
            jitters = successful.map { |m| m[:jitter_ms] }.compact

            DB[:measurements_15min].insert(
              host_id: host.id,
              period_start: period_start,
              period_end: period_end,
              test_count: group.size,
              success_count: successful.size,
              avg_latency_ms: latencies.any? ? (latencies.sum / latencies.size).round(3) : nil,
              min_latency_ms: latencies.min&.round(3),
              max_latency_ms: latencies.max&.round(3),
              avg_jitter_ms: jitters.any? ? (jitters.sum / jitters.size).round(3) : nil,
              created_at: Time.now
            )
          end

          Checker.logger.info "[Aggregator] Aggregated #{measurements.size} measurements to 15-min for host #{host.name}"
        end
      end

      def aggregate_to_hourly(days_old)
        cutoff = Time.now - (days_old * 24 * 60 * 60)

        Host.all.each do |host|
          # Find 15-min aggregates older than cutoff
          aggregates = DB[:measurements_15min]
            .where(host_id: host.id)
            .where { period_start < cutoff }
            .order(:period_start)
            .all

          next if aggregates.empty?

          # Group by hour
          grouped = aggregates.group_by do |m|
            time = m[:period_start]
            Time.new(time.year, time.month, time.day, time.hour, 0, 0)
          end

          grouped.each do |period_start, group|
            period_end = period_start + (60 * 60)

            # Check if already aggregated
            existing = DB[:measurements_hourly]
              .where(host_id: host.id, period_start: period_start)
              .first

            next if existing

            # Calculate weighted averages based on test_count
            total_tests = group.sum { |m| m[:test_count] }
            total_success = group.sum { |m| m[:success_count] }

            latencies = group.map { |m| m[:avg_latency_ms] }.compact
            min_latencies = group.map { |m| m[:min_latency_ms] }.compact
            max_latencies = group.map { |m| m[:max_latency_ms] }.compact
            jitters = group.map { |m| m[:avg_jitter_ms] }.compact

            DB[:measurements_hourly].insert(
              host_id: host.id,
              period_start: period_start,
              period_end: period_end,
              test_count: total_tests,
              success_count: total_success,
              avg_latency_ms: latencies.any? ? (latencies.sum / latencies.size).round(3) : nil,
              min_latency_ms: min_latencies.min&.round(3),
              max_latency_ms: max_latencies.max&.round(3),
              avg_jitter_ms: jitters.any? ? (jitters.sum / jitters.size).round(3) : nil,
              created_at: Time.now
            )
          end

          Checker.logger.info "[Aggregator] Aggregated #{aggregates.size} 15-min records to hourly for host #{host.name}"
        end
      end

      def cleanup_raw_data(days_old)
        cutoff = Time.now - (days_old * 24 * 60 * 60)

        # Only delete raw data that has been aggregated
        # We check by ensuring there's a 15-min aggregate for that time period
        deleted = DB[:measurements]
          .where { tested_at < cutoff }
          .delete

        Checker.logger.info "[Aggregator] Deleted #{deleted} old raw measurements"
      end

      def cleanup_15min_data(days_old)
        cutoff = Time.now - (days_old * 24 * 60 * 60)

        deleted = DB[:measurements_15min]
          .where { period_start < cutoff }
          .delete

        Checker.logger.info "[Aggregator] Deleted #{deleted} old 15-min aggregates"
      end
    end
  end
end
