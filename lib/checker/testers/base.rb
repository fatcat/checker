# frozen_string_literal: true

module Checker
  module Testers
    class Base
      attr_reader :test, :config

      def initialize(test, config = {})
        @test = test
        @config = config
        @record_results = config.fetch(:record_results, true)
      end

      def run
        raise NotImplementedError, "Subclasses must implement #run"
      end

      def record_result(reachable:, latency_ms: nil, jitter_ms: nil, http_status: nil, error_message: nil)
        # Skip recording if this is a validation test
        return unless @record_results

        # Check for outliers and retest if needed (only if outlier detection is enabled)
        if outlier_detection_enabled? && reachable && is_outlier?(latency_ms, jitter_ms)
          Checker.logger.info "[OutlierDetection] Potential outlier detected for #{test.host.name} (#{test.test_type}): latency=#{latency_ms}ms, jitter=#{jitter_ms}ms. Retesting..."

          # Retest without recording
          retest_result = self.class.new(test, config.merge(record_results: false)).run

          # If retest confirms the issue (similar bad result), keep original result
          if retest_confirms_outlier?(latency_ms, jitter_ms, retest_result)
            Checker.logger.info "[OutlierDetection] Retest confirmed outlier for #{test.host.name} (#{test.test_type}). Recording result."
          else
            # Retest shows normal result, use retest values instead
            Checker.logger.info "[OutlierDetection] Retest shows normal result for #{test.host.name} (#{test.test_type}). Using retest values."
            latency_ms = retest_result[:latency_ms]
            jitter_ms = retest_result[:jitter_ms]
            reachable = retest_result[:reachable]
            http_status = retest_result[:http_status]
            error_message = retest_result[:error_message]
          end
        end

        DB[:measurements].insert(
          host_id: test.host_id,
          test_type: test.test_type,
          reachable: reachable,
          latency_ms: latency_ms,
          jitter_ms: jitter_ms,
          http_status: http_status,
          error_message: error_message,
          tested_at: Time.now,
          created_at: Time.now
        )
      end

      protected

      def timeout
        config[:timeout] || 5
      end

      def address
        test.host.address
      end

      def port
        test.port
      end

      def host
        test.host
      end

      def outlier_detection_enabled?
        Configuration.get('outlier_detection_enabled').to_s == 'true'
      end

      def is_outlier?(latency_ms, jitter_ms)
        # Get recent measurements for this specific test type
        recent = DB[:measurements]
          .where(host_id: test.host_id, test_type: test.test_type)
          .order(Sequel.desc(:tested_at))
          .limit(50)
          .all

        return false if recent.empty? || recent.size < 5  # Need at least 5 samples

        # Get baseline average
        if test.test_type == 'jitter'
          values = recent.map { |m| m[:jitter_ms] }.compact
          current_value = jitter_ms
        else
          values = recent.map { |m| m[:latency_ms] }.compact
          current_value = latency_ms
        end

        return false if values.empty? || current_value.nil?

        baseline_avg = values.sum / values.size.to_f

        # Get thresholds from config
        multiplier = Configuration.get('outlier_threshold_multiplier').to_f
        min_diff_ms = Configuration.get('outlier_min_threshold_ms').to_f

        # Check if current value is an outlier
        diff = current_value - baseline_avg
        diff > min_diff_ms && current_value > (baseline_avg * multiplier)
      end

      def retest_confirms_outlier?(original_latency, original_jitter, retest_result)
        # Retest didn't succeed - confirms problem
        return true unless retest_result[:reachable]

        # Compare retest result to original outlier
        if test.test_type == 'jitter'
          original_value = original_jitter
          retest_value = retest_result[:jitter_ms]
        else
          original_value = original_latency
          retest_value = retest_result[:latency_ms]
        end

        return true if retest_value.nil?  # Retest failed to get value

        # If retest is similar to original outlier (within 50%), confirms the issue
        # Otherwise, original was a transient spike
        (retest_value - original_value).abs < (original_value * 0.5)
      end
    end
  end
end
