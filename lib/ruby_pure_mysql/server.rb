# frozen_string_literal: true

require 'socket'

module RubyPureMysql
  # Server クラスは、TCP 接続を受け付け、MySQL プロトコルのパケットを制御します。
  class Server
    def initialize(port)
      @server = TCPServer.new(port)
    end

    def run
      loop do
        client = @server.accept
        handle_client(client)
      rescue StandardError => e
        puts "Error: #{e.message}"
      ensure
        client&.close
      end
    end

    private

    def handle_client(client)
      write_handshake_v10(client)
      puts 'Handshake sent. Waiting for Client Response...'

      read_client_response(client)
    end

    def write_handshake_v10(client)
      payload = [
        10, '8.0.0-pure', 1, '12345678', 0, 0x0000
      ].pack('Ca*Va8Cv') # 複雑な結合を pack 一発に集約

      # MySQL Header: [Length(3), Sequence(1)]
      header = [payload.bytesize].pack('V')[0, 3] + [0].pack('C')
      client.write(header + payload)
    end

    def read_client_response(client)
      response_header = client.read(4)
      return unless response_header

      len = response_header.unpack1('V') & 0xFFFFFF
      client.read(len)
      puts "Received client response (#{len} bytes)."
    end
  end
end
