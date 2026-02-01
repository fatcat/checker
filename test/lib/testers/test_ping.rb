# frozen_string_literal: true

require_relative '../../test_helper'

class TestPing < Minitest::Test
  def test_returns_result_hash
    host = create_host(address: '127.0.0.1')
    test = create_test(host, test_type: 'ping')
    config = { ping_count: 5, ping_timeout: 5 }

    result = Checker::Testers.run_single(test, config)

    assert_kind_of Hash, result
    assert_includes result.keys, :reachable
    assert_includes result.keys, :latency_ms
  end

  def test_successful_ping_to_localhost
    host = create_host(address: '127.0.0.1')
    test = create_test(host, test_type: 'ping')
    config = { ping_timeout: 5 }

    result = Checker::Testers.run_single(test, config)

    assert result[:reachable]
    assert result[:latency_ms]
    assert_operator result[:latency_ms], :>, 0
    assert_equal 1, result[:samples]  # Single ping
  end

  def test_unreachable_host
    # Using a non-routable address
    host = create_host(address: '192.0.2.1') # TEST-NET-1 (RFC 5737)
    test = create_test(host, test_type: 'ping')
    config = { ping_count: 1, ping_timeout: 1 }

    result = Checker::Testers.run_single(test, config)

    refute result[:reachable]
    assert_includes result.keys, :error
  end
end
