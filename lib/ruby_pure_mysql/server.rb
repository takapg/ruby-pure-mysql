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
      
      # クライアントからの Login Response を待機 (Sequence ID: 1)
      return unless read_client_response(client)

      # ログイン成功を伝える OK Packet を送信 (Sequence ID: 2)
      write_ok_packet(client)
      
      # 本来はこの後に SELECT 1; などのコマンドを待つループが必要
      puts 'Login successful. implementation ends here for now.'
    end

    def write_handshake_v10(client)
      payload = handshake_v10_payload
      header = [payload.bytesize].pack('V')[0, 3] + [0].pack('C')
      client.write(header + payload)
    end

    def handshake_v10_payload
      [
        10, '8.0.0-pure', 1, '12345678', 0,
        0x0000, 33, 0x0002, 0x0000,
        21, "\0" * 10, "123456789012\0", "mysql_native_password\0"
      ].pack('Ca*Va8C v C v v C a10 a* a*')
    end

    def write_ok_packet(client)
      # OK Packet Payload: header(0x00), affected_rows(0), last_insert_id(0) ...
      payload = [0x00, 0x00, 0x00, 0x02, 0x00].pack('CCVvV')[0, 7]
      header = [payload.bytesize].pack('V')[0, 3] + [2].pack('C')
      client.write(header + payload)
      puts 'OK Packet sent.'
    end

    def read_client_response(client)
      response_header = client.read(4)
      return unless response_header

      len = response_header.unpack1('V') & 0xFFFFFF
      client.read(len)
      puts "Received client response (#{len} bytes)."
      true
    end
  end
end
