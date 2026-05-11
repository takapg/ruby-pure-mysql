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
      return unless authenticate(client)

      command_phase_loop(client)
    end

    def authenticate(client)
      write_handshake_v10(client)
      return false unless read_packet(client) # Login Response

      write_ok_packet(client) # Login OK
      true
    end

    def command_phase_loop(client)
      loop do
        header = client.read(4)
        break unless header

        len = header.unpack1('V') & 0xFFFFFF
        seq = header.unpack('C4')[3]
        payload = client.read(len)

        handle_command(client, payload, seq)
      end
    end

    def handle_command(client, payload, seq)
      command = payload[0].ord
      return unless command == 0x03 # COM_QUERY

      query = payload[1..]
      puts "Received Query: #{query}"
      write_select_one_response(client, seq + 1)
    end

    def write_select_one_response(client, seq)
      # 1. Column Count, 2. Column Definition
      write_raw_packet(client, [1].pack('C'), seq)
      col_def = ['def', '', '', '1', '1', 63, 11, 3, 0, 0].pack('Ca*Ca*Ca*Ca*Ca*C v V C v')
      write_raw_packet(client, col_def, seq + 1)

      # 3. EOF (MySQL 8.0), 4. Row Data, 5. EOF
      write_raw_packet(client, [0xfe, 0, 0, 0x02, 0].pack('CCv v'), seq + 2)
      write_raw_packet(client, [1, '1'].pack('Ca*'), seq + 3)
      write_raw_packet(client, [0xfe, 0, 0, 0x02, 0].pack('CCv v'), seq + 4)
    end

    def write_raw_packet(client, payload, seq)
      header = [payload.bytesize].pack('V')[0, 3] + [seq].pack('C')
      client.write(header + payload)
    end

    def write_handshake_v10(client)
      payload = [
        10, '8.0.0-pure', 1, '12345678', 0, 0x0000, 33, 0x0002, 0x0000,
        21, "\0" * 10, "123456789012\0", "mysql_native_password\0"
      ].pack('Ca*Va8C v C v v C a10 a* a*')
      write_raw_packet(client, payload, 0)
    end

    def write_ok_packet(client)
      payload = [0x00, 0x00, 0x00, 0x02, 0x00].pack('CCVvV')[0, 7]
      write_raw_packet(client, payload, 2)
    end

    def read_packet(client)
      header = client.read(4)
      return false unless header

      len = header.unpack1('V') & 0xFFFFFF
      client.read(len)
      true
    end
  end
end
