# frozen_string_literal: true

require_relative '../test_helper'

class TestScheduler < Minitest::Test
  def setup
    super
    @scheduler = Checker::Scheduler.new
  end

  def teardown
    @scheduler.stop if @scheduler.running?
    super
  end

  def test_scheduler_initialization
    assert_instance_of Checker::Scheduler, @scheduler
    refute @scheduler.running?
  end

  def test_scheduler_start_and_stop
    @scheduler.start
    assert @scheduler.running?

    @scheduler.stop
    refute @scheduler.running?
  end

  def test_run_test_for_host
    host = create_host(address: '127.0.0.1', jitter_enabled: false)
    test = create_test(host, test_type: 'ping')

    results = @scheduler.run_test_for_host(host.id)

    assert_kind_of Array, results
    refute_empty results, "Expected at least one result"
    # Verify results have expected structure
    results.each do |result|
      assert_includes result.keys, :reachable
      # Results may have latency_ms, jitter_ms, error, etc. depending on test type
    end
  end

  def test_run_test_for_disabled_host
    host = create_host(enabled: false)
    test = create_test(host)

    results = @scheduler.run_test_for_host(host.id)

    assert_empty results
  end

  def test_updates_next_test_at
    host = create_host(address: '127.0.0.1')
    test = create_test(host, test_type: 'ping')

    initial_next_test_at = test.next_test_at

    @scheduler.run_test_for_host(host.id)
    test.refresh

    # next_test_at should be updated
    refute_equal initial_next_test_at, test.next_test_at
    assert test.next_test_at
  end
end
