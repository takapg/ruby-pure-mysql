# frozen_string_literal: true

require_relative 'ruby_pure_mysql/server'

module RubyPureMysql
  def self.start(port: 3307)
    puts "Starting MySQL-compatible server on port #{port}..."
    Server.new(port).run
  end
end
