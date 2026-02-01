# frozen_string_literal: true

require_relative '../../test_helper'

class TestHttp < Minitest::Test
  def test_returns_result_hash
    host = create_host(address: 'httpbin.org')
    test = create_test(host, test_type: 'http', port: 80, http_scheme: 'http')
    config = { http_timeout: 10 }

    result = Checker::Testers.run_single(test, config)

    assert_kind_of Hash, result
    assert_includes result.keys, :reachable
    assert_includes result.keys, :http_status
  end

  def test_no_jitter_for_http
    host = create_host(address: 'httpbin.org')
    test = create_test(host, test_type: 'http', port: 80, http_scheme: 'http')
    config = { http_timeout: 10 }

    result = Checker::Testers.run_single(test, config)

    # HTTP tests should not have jitter
    refute_includes result.keys, :jitter_ms
  end
end
