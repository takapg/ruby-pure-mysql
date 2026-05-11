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
      return false unless read_packet(client)

      write_ok_packet(client)
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
      return unless payload[0].ord == 0x03 # COM_QUERY

      write_select_one_response(client, seq + 1)
    end

    def write_select_one_response(client, seq)
      # 1. Column Count (1列)
      write_raw_packet(client, [1].pack('C'), seq)

      # 2. Column Definition
      # 各文字列を [長さ, 文字列] のペアで定義。固定長部分は pack テンプレートで制御
      col_data = [
        3, 'def', 0, '', 0, '', 1, '1', 1, '1', 12, 33, 11, 3, 0, 0
      ]
      # テンプレート: C,a3, C,a0, C,a0, C,a1, C,a1, C, v, V, C, v, C
      write_raw_packet(client, col_data.pack('Ca3Ca0Ca0Ca1Ca1CvVCvC'), seq + 1)

      # 3. EOF (0xFE), 4. Row Data (len 1, "1"), 5. EOF (0xFE)
      eof = [0xfe, 0, 0, 0x22, 0].pack('CCv v')
      write_raw_packet(client, eof, seq + 2)
      write_raw_packet(client, [1, '1'].pack('Ca1'), seq + 3)
      write_raw_packet(client, eof, seq + 4)
    end

    def write_raw_packet(client, payload, seq)
      header = [payload.bytesize].pack('V')[0, 3] + [seq % 256].pack('C')
      client.write(header + payload)
    end

    def write_handshake_v10(client)
      payload = [
        10, "8.0.0-pure\0", 1, '12345678', 0, 0x0000, 33, 0x0002, 0x0000,
        21, "\0" * 10, "123456789012\0", "mysql_native_password\0"
      ].pack('Ca*Va8C v C v v C a10 a* a*')
      write_raw_packet(client, payload, 0)
    end

    def write_ok_packet(client)
      # OK_Packet: header(0), affected_rows(0), last_insert_id(0), status(2), warnings(0)
      payload = [0x00, 0, 0, 0x0002, 0].pack('CC C v v')
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
