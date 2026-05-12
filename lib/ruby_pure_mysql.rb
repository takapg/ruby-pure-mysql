# frozen_string_literal: true

require_relative 'ruby_pure_mysql/constants'
require_relative 'ruby_pure_mysql/protocol/packet_helper'

require_relative 'ruby_pure_mysql/protocol/base_packet'

require_relative 'ruby_pure_mysql/protocol/handshake_packet'

require_relative 'ruby_pure_mysql/server'

# RubyPureMysql は、Ruby による純粋な MySQL プロトコルの再実装を提供します。
module RubyPureMysql
  def self.start(port: 3307)
    puts "Starting MySQL-compatible server on port #{port}..."
    Server.new(port).run
  end
end
