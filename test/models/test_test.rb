# frozen_string_literal: true

require_relative '../test_helper'

class TestTest < Minitest::Test
  def test_valid_ping_test_creation
    host = create_host
    test = create_test(host, test_type: 'ping')
    assert test.valid?
  end

  def test_valid_tcp_test_creation
    host = create_host
    test = create_test(host, test_type: 'tcp', port: 80)
    assert test.valid?
  end

  def test_valid_http_test_creation
    host = create_host
    test = create_test(host, test_type: 'http', port: 443, http_scheme: 'https')
    assert test.valid?
  end

  def test_valid_dns_test_creation
    host = create_host(address: '8.8.8.8')
    test = create_test(host, test_type: 'dns', dns_query_hostname: 'google.com')
    assert test.valid?
  end

  def test_requires_host_id
    test = Checker::Test.new(test_type: 'ping')
    refute test.valid?
    assert test.errors.on(:host_id)
  end

  def test_requires_test_type
    host = create_host
    test = Checker::Test.new(host_id: host.id)
    refute test.valid?
    assert test.errors.on(:test_type)
  end

  def test_validates_test_type
    host = create_host
    test = Checker::Test.new(host_id: host.id, test_type: 'invalid')
    refute test.valid?
  end

  def test_tcp_requires_port
    host = create_host
    test = Checker::Test.new(host_id: host.id, test_type: 'tcp')
    refute test.valid?
    assert test.errors.on(:port)
  end

  def test_http_requires_port
    host = create_host
    test = Checker::Test.new(host_id: host.id, test_type: 'http', http_scheme: 'http')
    refute test.valid?
    assert test.errors.on(:port)
  end

  def test_http_requires_scheme
    host = create_host
    test = Checker::Test.new(host_id: host.id, test_type: 'http', port: 80)
    refute test.valid?
    assert test.errors.on(:http_scheme)
  end

  def test_dns_requires_query_hostname
    host = create_host
    test = Checker::Test.new(host_id: host.id, test_type: 'dns')
    refute test.valid?
    assert test.errors.on(:dns_query_hostname)
  end

  def test_status_never_with_no_measurements
    host = create_host
    test = create_test(host)

    assert_equal 'never', test.status
  end

  def test_status_success_with_reachable_measurement
    host = create_host
    test = create_test(host)
    create_measurement(host, test, reachable: true, latency_ms: 50.0)

    assert_equal 'success', test.status
  end

  def test_status_degraded_with_high_latency
    host = create_host
    test = create_test(host, test_type: 'ping')
    create_measurement(host, test, reachable: true, latency_ms: 1500.0)

    assert_equal 'degraded', test.status
  end

  def test_status_failure_with_unreachable
    host = create_host
    test = create_test(host)
    create_measurement(host, test, reachable: false)

    assert_equal 'failure', test.status
  end

  def test_status_color_mapping
    host = create_host
    test = create_test(host)

    assert_equal 'gray', test.status_color # never

    create_measurement(host, test, reachable: true)
    test.refresh
    assert_equal 'green', test.status_color # success
  end

  def test_calculate_next_test_time
    host = create_host(randomness_percent: 10)
    test = create_test(host)
    base_interval = 300 # 5 minutes

    next_time = test.calculate_next_test_time(base_interval)

    # Should be roughly 5 minutes from now, +/- 10%
    min_time = Time.now + base_interval - 30
    max_time = Time.now + base_interval + 30

    assert_operator next_time, :>=, min_time
    assert_operator next_time, :<=, max_time
  end

  def test_enabled_scope
    host = create_host
    enabled_test = create_test(host, enabled: true)
    disabled_test = create_test(host, enabled: false, test_type: 'tcp', port: 80)

    enabled_tests = Checker::Test.enabled.all
    assert_includes enabled_tests, enabled_test
    refute_includes enabled_tests, disabled_test
  end
end
