# frozen_string_literal: true

module Checker
  VERSION = '0.1.0'
end

require_relative 'checker/logger'
require_relative 'checker/theme_loader'
require_relative 'checker/testers'
require_relative 'checker/aggregator'
require_relative 'checker/scheduler'
