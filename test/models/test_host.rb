# frozen_string_literal: true

require_relative '../test_helper'

class TestHost < Minitest::Test
  def test_valid_host_creation
    host = create_host(name: 'Google DNS', address: '8.8.8.8')
    assert host.valid?
    assert_equal 'Google DNS', host.name
    assert_equal '8.8.8.8', host.address
  end

  def test_requires_name
    host = Checker::Host.new(address: '8.8.8.8')
    refute host.valid?
    assert host.errors.on(:name)
  end

  def test_requires_address
    host = Checker::Host.new(name: 'Test')
    refute host.valid?
    assert host.errors.on(:address)
  end

  def test_validates_ipv4_address
    host = Checker::Host.new(name: 'Test', address: '8.8.8.8', enabled: true)
    assert host.valid?
  end

  def test_validates_hostname
    host = Checker::Host.new(name: 'Test', address: 'google.com', enabled: true)
    assert host.valid?
  end

  def test_rejects_invalid_address
    host = Checker::Host.new(name: 'Test', address: '999.999.999.999', enabled: true)
    refute host.valid?
  end

  def test_randomness_percent_within_range
    host = Checker::Host.new(name: 'Test', address: '8.8.8.8', randomness_percent: 25, enabled: true)
    assert host.valid?
  end

  def test_rejects_randomness_percent_above_50
    host = Checker::Host.new(name: 'Test', address: '8.8.8.8', randomness_percent: 51, enabled: true)
    refute host.valid?
  end

  def test_rejects_negative_randomness_percent
    host = Checker::Host.new(name: 'Test', address: '8.8.8.8', randomness_percent: -1, enabled: true)
    refute host.valid?
  end

  def test_enabled_scope
    enabled_host = create_host(enabled: true)
    disabled_host = create_host(enabled: false)

    enabled_hosts = Checker::Host.enabled.all
    assert_includes enabled_hosts, enabled_host
    refute_includes enabled_hosts, disabled_host
  end

  def test_has_tests_association
    host = create_host
    test = create_test(host)

    assert_equal 1, host.tests.count
    assert_equal test.id, host.tests.first.id
  end

  def test_has_ping_test
    host = create_host
    create_test(host, test_type: 'ping')

    assert host.has_ping_test?
  end

  def test_does_not_have_ping_test
    host = create_host
    create_test(host, test_type: 'tcp', port: 80)

    refute host.has_ping_test?
  end

  def test_overall_status_with_successful_test
    host = create_host
    test = create_test(host)
    create_measurement(host, test, reachable: true)

    assert host.overall_status
  end

  def test_overall_status_with_failed_test
    host = create_host
    test = create_test(host)
    create_measurement(host, test, reachable: false)

    refute host.overall_status
  end

  def test_overall_status_with_no_tests
    host = create_host

    refute host.overall_status
  end

  def test_jitter_enabled_requires_address
    host = Checker::Host.new(name: 'Test', address: '', jitter_enabled: true)
    refute host.valid?
    assert host.errors.on(:jitter_enabled)
  end

  def test_creates_jitter_test_when_jitter_enabled
    host = create_host(jitter_enabled: true)
    jitter_test = host.tests_dataset.where(test_type: 'jitter').first

    assert jitter_test
    assert jitter_test.enabled
  end

  def test_deletes_jitter_test_when_disabled
    host = create_host(jitter_enabled: true)
    jitter_test_id = host.tests_dataset.where(test_type: 'jitter').first.id

    host.update(jitter_enabled: false)

    assert_nil Checker::Test[jitter_test_id]
  end
end
