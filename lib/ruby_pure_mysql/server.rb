# frozen_string_literal: true

require 'socket'

module RubyPureMysql
  class Server
    def initialize(port)
      @server = TCPServer.new(port)
    end

    def run
      loop do
        client = @server.accept
        handle_client(client)
      rescue => e
        puts "Error: #{e.message}"
      ensure
        client&.close
      end
    end

    private

    def handle_client(client)
      # Handshake Packet の作成 (Protocol version 10)
      # MySQLは接続直後にサーバーから挨拶を投げる必要がある
      
      protocol_version = [10].pack('C')
      server_version = "8.0.0-pure\0"
      thread_id = [1].pack('V')
      salt_part1 = "12345678\0" # 8 bytes + null
      capabilities = [0x0000].pack('v') # Lower 2 bytes
      
      payload = protocol_version + server_version + thread_id + salt_part1 + capabilities
      
      # MySQL Packet Header: [Payload Length (3 bytes), Sequence ID (1 byte)]
      header = [payload.bytesize].pack('V')[0, 3] + [0].pack('C')
      
      client.write(header + payload)
      puts "Handshake sent. Waiting for Client Response..."

      # クライアントからのレスポンスを読み取る（認証リクエストなど）
      # 本来はここでパケットを解析するが、一旦読み捨てて接続を維持
      response_header = client.read(4)
      if response_header
        len = response_header.unpack('V')[0] & 0xFFFFFF
        client.read(len)
        puts "Received client response (#{len} bytes). Implementation ends here for now."
      end
    end
  end
end
