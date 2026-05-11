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
      # 規格に準拠した最低限のフィールド構成
      protocol_version = 10
      server_version = "8.0.0-pure\0"
      thread_id = 1
      salt_part1 = "12345678" # 8 bytes
      filter = 0
      capability_flags = 0x0000 # Lower 2 bytes
      char_set = 33 # utf8_general_ci
      status_flags = 0x0002 # SERVER_STATUS_AUTOCOMMIT
      capability_flags_upper = 0x0000
      auth_plugin_data_len = 21 # Salt total length
      reserved = "\0" * 10
      salt_part2 = "123456789012\0" # 13 bytes (including null)
      auth_plugin_name = "mysql_native_password\0"

      payload = [
        protocol_version, server_version, thread_id, salt_part1, filter,
        capability_flags, char_set, status_flags, capability_flags_upper,
        auth_plugin_data_len, reserved, salt_part2, auth_plugin_name
      ].pack('Ca*Va8C v C v v C a10 a* a*')

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
