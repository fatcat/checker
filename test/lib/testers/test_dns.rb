# frozen_string_literal: true

require_relative '../../test_helper'

class TestDns < Minitest::Test
  def test_returns_result_hash
    host = create_host(address: '8.8.8.8')
    test = create_test(host, test_type: 'dns', dns_query_hostname: 'google.com')
    config = { dns_timeout: 5 }

    result = Checker::Testers.run_single(test, config)

    assert_kind_of Hash, result
    assert_includes result.keys, :reachable
  end

  def test_no_jitter_for_dns
    host = create_host(address: '8.8.8.8')
    test = create_test(host, test_type: 'dns', dns_query_hostname: 'google.com')
    config = { dns_timeout: 5 }

    result = Checker::Testers.run_single(test, config)

    # DNS tests should not have jitter
    refute_includes result.keys, :jitter_ms
  end

  def test_successful_dns_resolution
    host = create_host(address: '8.8.8.8')
    test = create_test(host, test_type: 'dns', dns_query_hostname: 'google.com')
    config = { dns_timeout: 5 }

    result = Checker::Testers.run_single(test, config)

    assert result[:reachable]
    assert result[:latency_ms]
    assert_operator result[:latency_ms], :>, 0
  end
end
