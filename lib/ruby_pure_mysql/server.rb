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

      write_select_one_response(client, seq)
    end

    def write_select_one_response(client, seq)
      # クエリ応答シーケンス: IDをインクリメントしながら順番に送信
      write_raw_packet(client, [1].pack('C'), seq + 1)
      write_raw_packet(client, col_def_payload, seq + 2)
      write_raw_packet(client, eof_payload, seq + 3)
      write_raw_packet(client, lenenc_str('1'), seq + 4) # Row Data
      write_raw_packet(client, eof_payload, seq + 5)
    end

    def col_def_payload
      # Length-Encoded String を用いてフィールドを定義
      [
        lenenc_str('def'), lenenc_str(''), lenenc_str(''),
        lenenc_str(''), lenenc_str('1'), lenenc_str(''),
        "\x0c", [33, 11, 8, 0, 0, 0].pack('vVCvCv') # 12 bytes の固定長フィールド
      ].join
    end

    def lenenc_str(str)
      # MySQL の可変長文字列（Length-Encoded String）を生成
      str.empty? ? "\x00" : [str.bytesize, str].pack('Ca*')
    end

    def eof_payload
      # 0xFE: EOF Header, 0: Warnings, 2: Status (SERVER_STATUS_AUTOCOMMIT)
      [0xfe, 0, 2].pack('Cvv')
    end

    def write_raw_packet(client, payload, seq)
      header = [payload.bytesize].pack('V')[0, 3] + [seq % 256].pack('C')
      client.write(header + payload)
    end

    def write_handshake_v10(client)
      # 0xA285: CLIENT_PROTOCOL_41 などの基本機能をサポートしていることを宣言
      payload = [
        10, "8.0.0-pure\0", 1, '12345678', 0, 0xA285, 33, 0x0002, 0x0008,
        21, "\0" * 10, "123456789012\0", "mysql_native_password\0"
      ].pack('Ca*Va8CvCvvCa10a*a*')
      write_raw_packet(client, payload, 0)
    end

    def write_ok_packet(client)
      payload = [0x00, 0, 0, 2, 0].pack('CCCvv')
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
