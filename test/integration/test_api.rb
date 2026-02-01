# frozen_string_literal: true

require_relative '../test_helper'
require 'rack/test'

# Load Sinatra app
require_relative '../../app/app'

class TestApi < Minitest::Test
  include Rack::Test::Methods

  def app
    Checker::App
  end

  def test_health_endpoint
    get '/health'
    assert last_response.ok?

    data = JSON.parse(last_response.body)
    assert_equal 'ok', data['status']
  end

  def test_get_hosts_empty
    get '/api/hosts'
    assert last_response.ok?

    data = JSON.parse(last_response.body)
    assert_kind_of Hash, data
    assert_empty data['hosts']
  end

  def test_create_host
    post '/api/hosts', {
      name: 'Test Host',
      address: '8.8.8.8',
      enabled: true,
      tests: []
    }.to_json, { 'CONTENT_TYPE' => 'application/json' }

    assert_equal 201, last_response.status
    data = JSON.parse(last_response.body)
    assert_equal 'Test Host', data['name']
    assert_equal '8.8.8.8', data['address']
  end

  def test_get_hosts_after_creation
    create_host(name: 'Host 1', address: '8.8.8.8')
    create_host(name: 'Host 2', address: '1.1.1.1')

    get '/api/hosts'
    assert last_response.ok?

    data = JSON.parse(last_response.body)
    assert_equal 2, data['hosts'].length
  end

  def test_get_single_host
    host = create_host

    get "/api/hosts/#{host.id}"
    assert last_response.ok?

    data = JSON.parse(last_response.body)
    assert_equal host.name, data['name']
  end

  def test_update_host
    host = create_host

    put "/api/hosts/#{host.id}", {
      name: 'Updated Name'
    }.to_json, { 'CONTENT_TYPE' => 'application/json' }

    assert last_response.ok?
    data = JSON.parse(last_response.body)
    assert_equal 'Updated Name', data['name']
  end

  def test_delete_host
    host = create_host

    delete "/api/hosts/#{host.id}"
    assert_equal 204, last_response.status

    # Verify host is deleted
    get "/api/hosts/#{host.id}"
    assert_equal 404, last_response.status
  end

  def test_invalid_host_creation
    post '/api/hosts', {
      name: 'Invalid',
      address: '999.999.999.999',
      tests: []
    }.to_json, { 'CONTENT_TYPE' => 'application/json' }

    assert_equal 422, last_response.status
    data = JSON.parse(last_response.body)
    assert_includes data['error'], 'validation'
  end
end
