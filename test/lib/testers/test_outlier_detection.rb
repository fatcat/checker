# frozen_string_literal: true

require_relative '../../test_helper'

class TestOutlierDetection < Minitest::Test
  def setup
    super
    # Ensure outlier detection is enabled with known threshold
    DB[:settings].insert(key: 'outlier_detection_enabled', value: 'true')
    DB[:settings].insert(key: 'outlier_threshold_multiplier', value: '5')
  end

  # Test calculate_median helper

  def test_calculate_median_odd_count
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Odd number of values: [1, 2, 3, 4, 5] -> median = 3
    values = [5, 1, 3, 2, 4]
    assert_equal 3, tester.send(:calculate_median, values)
  end

  def test_calculate_median_even_count
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Even number of values: [1, 2, 3, 4] -> median = (2+3)/2 = 2.5
    values = [4, 1, 3, 2]
    assert_equal 2.5, tester.send(:calculate_median, values)
  end

  # Test is_outlier? detection

  def test_is_outlier_returns_false_with_insufficient_samples
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Only 3 measurements (need at least 5)
    3.times do |i|
      create_measurement(host, test_record, latency_ms: 20.0, tested_at: Time.now - i)
    end

    # Even an extreme value shouldn't trigger with insufficient samples
    refute tester.send(:is_outlier?, 1000.0, nil)
  end

  def test_is_outlier_returns_false_for_normal_value
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Create baseline with median of 20ms
    10.times do |i|
      create_measurement(host, test_record, latency_ms: 20.0, tested_at: Time.now - i)
    end

    # 40ms is 2x median (20ms) - should NOT be an outlier (needs > 5x = 100ms)
    refute tester.send(:is_outlier?, 40.0, nil)
  end

  def test_is_outlier_returns_false_when_just_under_threshold
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Create baseline with median of 20ms
    10.times do |i|
      create_measurement(host, test_record, latency_ms: 20.0, tested_at: Time.now - i)
    end

    # 100ms is exactly 5x median - should NOT be an outlier (needs > 5x)
    refute tester.send(:is_outlier?, 100.0, nil)
  end

  def test_is_outlier_returns_true_when_exceeds_threshold
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Create baseline with median of 20ms
    10.times do |i|
      create_measurement(host, test_record, latency_ms: 20.0, tested_at: Time.now - i)
    end

    # 150ms is 7.5x median (20ms) - should be an outlier (> 5x = 100ms)
    assert tester.send(:is_outlier?, 150.0, nil)
  end

  def test_is_outlier_uses_median_not_mean
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Create measurements with some high outliers already in baseline
    # Values: 10, 10, 10, 10, 10, 10, 10, 500, 500
    # Mean = 130ms, Median = 10ms
    7.times do |i|
      create_measurement(host, test_record, latency_ms: 10.0, tested_at: Time.now - i)
    end
    2.times do |i|
      create_measurement(host, test_record, latency_ms: 500.0, tested_at: Time.now - (7 + i))
    end

    # 60ms would NOT be an outlier if using median (60 > 10*5 = 50, so it IS)
    # But with mean (130ms), 60ms would be below threshold (130*5 = 650)
    # This test confirms we use median: 60ms > 50ms threshold
    assert tester.send(:is_outlier?, 60.0, nil)
  end

  def test_is_outlier_uses_jitter_for_jitter_test_type
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'jitter')
    tester = Checker::Testers::Jitter.new(test_record, {})

    # Create baseline with median of 10ms jitter
    10.times do |i|
      create_measurement(host, test_record, jitter_ms: 10.0, latency_ms: nil, tested_at: Time.now - i)
    end

    # 40ms jitter is 4x median - NOT an outlier
    refute tester.send(:is_outlier?, nil, 40.0)

    # 60ms jitter is 6x median - IS an outlier (> 5x = 50ms)
    assert tester.send(:is_outlier?, nil, 60.0)
  end

  # Test retest_confirms_outlier?

  def test_retest_confirms_when_retest_fails
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    retest_result = { reachable: false, error: 'Host unreachable' }

    assert tester.send(:retest_confirms_outlier?, 1000.0, nil, retest_result)
  end

  def test_retest_confirms_when_retest_similar_to_original
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Retest shows 900ms, original was 1000ms (within 50%)
    retest_result = { reachable: true, latency_ms: 900.0 }

    assert tester.send(:retest_confirms_outlier?, 1000.0, nil, retest_result)
  end

  def test_retest_does_not_confirm_when_retest_much_better
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Retest shows 100ms, original was 1000ms (not within 50%)
    retest_result = { reachable: true, latency_ms: 100.0 }

    refute tester.send(:retest_confirms_outlier?, 1000.0, nil, retest_result)
  end

  def test_retest_confirms_when_retest_value_nil
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Retest succeeded but didn't return a value
    retest_result = { reachable: true, latency_ms: nil }

    assert tester.send(:retest_confirms_outlier?, 1000.0, nil, retest_result)
  end

  def test_retest_uses_jitter_for_jitter_test_type
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'jitter')
    tester = Checker::Testers::Jitter.new(test_record, {})

    # Retest shows 450ms jitter, original was 500ms jitter (within 50%)
    retest_result = { reachable: true, jitter_ms: 450.0 }

    assert tester.send(:retest_confirms_outlier?, nil, 500.0, retest_result)

    # Retest shows 100ms jitter, original was 500ms jitter (not within 50%)
    retest_result = { reachable: true, jitter_ms: 100.0 }

    refute tester.send(:retest_confirms_outlier?, nil, 500.0, retest_result)
  end

  # Test outlier detection enabled/disabled

  def test_outlier_detection_can_be_disabled
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Disable outlier detection
    DB[:settings].where(key: 'outlier_detection_enabled').update(value: 'false')

    refute tester.send(:outlier_detection_enabled?)
  end

  def test_outlier_detection_enabled_by_default
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')
    tester = Checker::Testers::Ping.new(test_record, {})

    # Clear settings to test default
    DB[:settings].where(key: 'outlier_detection_enabled').delete

    assert tester.send(:outlier_detection_enabled?)
  end

  # Test record_results flag prevents outlier detection loop

  def test_record_results_false_skips_recording
    host = create_host(address: '127.0.0.1')
    test_record = create_test(host, test_type: 'ping')

    initial_count = DB[:measurements].count

    # Create tester with record_results: false (used for retests)
    tester = Checker::Testers::Ping.new(test_record, { record_results: false })
    tester.send(:record_result, reachable: true, latency_ms: 100.0)

    # Should not have recorded anything
    assert_equal initial_count, DB[:measurements].count
  end
end
