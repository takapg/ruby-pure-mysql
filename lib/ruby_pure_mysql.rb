# frozen_string_literal: true

require_relative 'ruby_pure_mysql/constants'
require_relative 'ruby_pure_mysql/errors'

require_relative 'ruby_pure_mysql/protocol/packet_helper'

require_relative 'ruby_pure_mysql/protocol/base_packet'

require_relative 'ruby_pure_mysql/protocol/column_definition_packet'
require_relative 'ruby_pure_mysql/protocol/eof_packet'
require_relative 'ruby_pure_mysql/protocol/handshake_packet'
require_relative 'ruby_pure_mysql/protocol/ok_packet'

require_relative 'ruby_pure_mysql/packet_io'
require_relative 'ruby_pure_mysql/server'

# RubyPureMysql は、Ruby による純粋な MySQL プロトコルの再実装を提供します。
module RubyPureMysql
  def self.start(host: '127.0.0.1', port: 3307)
    puts "Starting MySQL-compatible server on #{host}:#{port}..."
    Server.new(host:, port:).run
  end
end
