# frozen_string_literal: true

require 'socket'
require 'timeout'

module RubyPureMysql
  # ソケットからの低レベルなパケット読み取りを制御します。
  class PacketReader
    def initialize(client, timeout)
      @client = client
      @timeout = timeout
    end

    def read_exact(length)
      buffer = +''
      while buffer.bytesize < length
        chunk = @client.read_nonblock(length - buffer.bytesize, exception: false)
        case chunk
        when :wait_readable then wait_socket
        when nil then raise InsufficientDataError, 'Closed'
        else buffer << chunk
        end
      end
      buffer
    end

    private

    def wait_socket
      result = IO.select([@client], nil, nil, @timeout)
      raise Timeout::Error, 'Read timeout' if result.nil?
    end
  end
end
