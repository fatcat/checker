# frozen_string_literal: true

require_relative '../test_helper'

class TestMeasurement < Minitest::Test
  def test_valid_measurement_creation
    host = create_host
    test = create_test(host)
    measurement = create_measurement(host, test)

    assert measurement.valid?
    assert_equal host.id, measurement.host_id
    assert_equal 'ping', measurement.test_type
  end

  def test_records_latency
    host = create_host
    test = create_test(host)
    measurement = create_measurement(host, test, latency_ms: 25.5)

    assert_equal 25.5, measurement.latency_ms
  end

  def test_records_reachability
    host = create_host
    test = create_test(host)
    measurement = create_measurement(host, test, reachable: false)

    refute measurement.reachable
  end

  def test_records_jitter_for_ping
    host = create_host
    test = create_test(host, test_type: 'ping')
    measurement = create_measurement(host, test, jitter_ms: 5.2)

    assert_equal 5.2, measurement.jitter_ms
  end

  def test_records_http_status
    host = create_host
    test = create_test(host, test_type: 'http', port: 443, http_scheme: 'https')
    measurement = create_measurement(host, test, http_status: 200)

    assert_equal 200, measurement.http_status
  end

  def test_records_error_message
    host = create_host
    test = create_test(host)
    measurement = create_measurement(host, test, error_message: 'Connection timeout')

    assert_equal 'Connection timeout', measurement.error_message
  end

  def test_for_host_query
    host1 = create_host(name: 'Host 1')
    host2 = create_host(name: 'Host 2')
    test1 = create_test(host1)
    test2 = create_test(host2)

    m1 = create_measurement(host1, test1)
    m2 = create_measurement(host2, test2)

    since = Time.now - 3600
    until_time = Time.now + 3600

    measurements = Checker::Measurement.for_host(host1.id, since: since, until_time: until_time).all

    assert_includes measurements, m1
    refute_includes measurements, m2
  end

  def test_time_range_conversion
    assert_equal 3600, Checker::Measurement.time_range_to_interval('1h')
    assert_equal 21600, Checker::Measurement.time_range_to_interval('6h')
    assert_equal 86400, Checker::Measurement.time_range_to_interval('24h')
    assert_equal 604800, Checker::Measurement.time_range_to_interval('7d')
    assert_equal 2592000, Checker::Measurement.time_range_to_interval('30d')
  end

  def test_has_timestamps
    host = create_host
    test = create_test(host)
    measurement = create_measurement(host, test)

    assert measurement.tested_at
    assert measurement.created_at
  end
end
