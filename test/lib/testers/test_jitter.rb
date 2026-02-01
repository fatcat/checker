# frozen_string_literal: true

require_relative '../../test_helper'

class TestJitter < Minitest::Test
  def test_returns_result_hash
    host = create_host(address: '127.0.0.1')
    test = create_test(host, test_type: 'jitter')
    config = { ping_timeout: 5 }

    result = Checker::Testers.run_single(test, config)

    assert_kind_of Hash, result
    assert_includes result.keys, :reachable
    assert_includes result.keys, :latency_ms
    assert_includes result.keys, :jitter_ms
  end

  def test_successful_jitter_calculation
    host = create_host(address: '127.0.0.1')
    test = create_test(host, test_type: 'jitter')
    config = { ping_timeout: 5 }

    result = Checker::Testers.run_single(test, config)

    assert result[:reachable]
    assert result[:latency_ms]
    assert result[:jitter_ms]
    assert_operator result[:latency_ms], :>, 0
    assert_operator result[:jitter_ms], :>=, 0  # Jitter can be 0
    assert_equal 5, result[:samples]  # 5 pings
  end

  def test_unreachable_host
    # Using a non-routable address
    host = create_host(address: '192.0.2.1') # TEST-NET-1 (RFC 5737)
    test = create_test(host, test_type: 'jitter')
    config = { ping_timeout: 1 }

    result = Checker::Testers.run_single(test, config)

    refute result[:reachable]
    assert_includes result.keys, :error
    assert_match /unreachable/i, result[:error]
  end
end
