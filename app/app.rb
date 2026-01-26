# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'sinatra/reloader'
require 'sequel'
require 'json'

module Checker
  class App < Sinatra::Base
    configure do
      set :root, File.expand_path('..', __dir__)
      set :views, File.join(root, 'app', 'views')
      set :public_folder, File.join(root, 'public')

      enable :logging
      enable :static
    end

    configure :development do
      register Sinatra::Reloader
    end

    helpers do
      def json_body
        JSON.parse(request.body.read, symbolize_names: true)
      rescue JSON::ParserError
        halt 400, json(error: 'Invalid JSON')
      end
    end

    # Health check endpoint
    get '/health' do
      json status: 'ok', timestamp: Time.now.iso8601
    end

    # Root route - serves the dashboard
    get '/' do
      erb :dashboard
    end

    # Load route files
    Dir[File.join(__dir__, 'routes', '*.rb')].each { |file| require file }
  end
end
