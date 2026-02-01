# frozen_string_literal: true

require_relative '../../test_helper'

class TestTcp < Minitest::Test
  def test_returns_result_hash
    host = create_host(address: '127.0.0.1')
    test = create_test(host, test_type: 'tcp', port: 22) # SSH usually running
    config = { tcp_timeout: 5 }

    result = Checker::Testers.run_single(test, config)

    assert_kind_of Hash, result
    assert_includes result.keys, :reachable
    assert_includes result.keys, :latency_ms
  end

  def test_no_jitter_for_tcp
    host = create_host(address: '127.0.0.1')
    test = create_test(host, test_type: 'tcp', port: 22)
    config = { tcp_timeout: 5 }

    result = Checker::Testers.run_single(test, config)

    # TCP tests should not have jitter
    refute_includes result.keys, :jitter_ms
  end

  def test_connection_refused
    # Try to connect to a port that's unlikely to be open
    host = create_host(address: '127.0.0.1')
    test = create_test(host, test_type: 'tcp', port: 9999)
    config = { tcp_timeout: 1 }

    result = Checker::Testers.run_single(test, config)

    refute result[:reachable]
    assert_includes result.keys, :error
  end
end
