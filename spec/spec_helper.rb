# frozen_string_literal: true

require 'bundler/setup'
require 'mysql2'

RSpec.configure do |config|
  config.color = true
  config.formatter = :documentation
end
