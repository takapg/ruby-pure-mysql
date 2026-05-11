# frozen_string_literal: true

require 'socket'

module RubyPureMysql
  # Custom exceptions for MySQL protocol errors
  class ProtocolError < StandardError; end
  class AuthenticationError < StandardError; end
  class InsufficientDataError < ProtocolError; end

  # Server クラスは、TCP 接続を受け付け、MySQL プロトコルのフェーズを管理します。
  class Server
    MAX_PACKET_LEN = 0xFF_FF_FF # 16,777,215 bytes
    READ_TIMEOUT = 5

    def initialize(port)
      @server = TCPServer.new(port)
    end

    def run
      loop do
        client = @server.accept
        handle_client(client)
      rescue ProtocolError, AuthenticationError, Timeout::Error, Errno::ECONNRESET, Errno::EPIPE => e
        puts "Expected error: #{e.class.name}: #{e.message}"
      ensure
        client&.close
      end
    end

    private

    def handle_client(client)
      reader = PacketReader.new(client, READ_TIMEOUT)
      return unless authenticate(client, reader)

      command_phase_loop(client, reader)
    rescue StandardError => e
      puts "Unexpected error: #{e.class.name}: #{e.message}"
      puts "Backtrace:\n#{e.backtrace.join("\n")}"
      raise e
    end

    def authenticate(client, reader)
      write_handshake_v10(client)
      # クライアントからのハンドシェイクレスポンスを読み飛ばす（認証なし前提）
      return false unless read_next_packet(reader)

      write_ok_packet(client)
      true
    end

    def command_phase_loop(client, reader)
      loop do
        payload, seq = read_next_packet(reader)
        break unless payload
        break unless dispatch_command(client, payload, seq)
      rescue InsufficientDataError
        break
      end
    end

    def dispatch_command(client, payload, seq)
      raise ProtocolError, 'empty command packet' if payload.empty?

      command = payload.getbyte(0)
      case command
      when 0x01 then false # COM_QUIT
      when 0x03 then handle_query(client, payload[1..], seq)
      else
        write_err_packet(client, seq, "Unknown command: 0x#{command.to_s(16).upcase}")
        true
      end
    end

    def handle_query(client, sql, seq)
      normalized_sql = sql.strip.upcase.chomp(';')

      if normalized_sql == 'SELECT 1'
        write_select_one_response(client, seq)
      else
        write_err_packet(client, seq, "Unsupported query: #{sql}")
      end
      true
    end

    def read_next_packet(reader)
      header = reader.read_exact(4)
      return nil unless header

      len = header.unpack1('V') & 0xFFFFFF
      raise ProtocolError, "Invalid packet length: #{len}" if len <= 0 || len > MAX_PACKET_LEN

      seq = header.getbyte(3)
      [reader.read_exact(len), seq]
    end

    def write_select_one_response(client, seq)
      write_raw_packet(client, [1].pack('C'), seq + 1)
      write_raw_packet(client, col_def_payload, seq + 2)
      write_raw_packet(client, eof_payload, seq + 3)
      write_raw_packet(client, lenenc_str('1'), seq + 4)
      write_raw_packet(client, eof_payload, seq + 5)
    end

    def col_def_payload
      [
        lenenc_str('def'), lenenc_str(''), lenenc_str(''),
        lenenc_str(''), lenenc_str('1'), lenenc_str(''),
        "\x0c", [33, 11, 8, 0, 0, 0].pack('vVCvCv')
      ].join
    end

    def lenenc_str(str)
      str.empty? ? "\x00" : [str.bytesize, str].pack('Ca*')
    end

    def eof_payload
      [0xfe, 0, 2].pack('Cvv')
    end

    def write_raw_packet(client, payload, seq)
      header = [payload.bytesize].pack('V')[0, 3] + [seq % 256].pack('C')
      client.write(header + payload)
    end

    def write_handshake_v10(client)
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

    def write_err_packet(client, seq, message)
      payload = [0xFF, 1047, '#', '42000', message].pack('Cv a a5 a*')
      write_raw_packet(client, payload, seq + 1)
    end
  end

  # 低レイヤのバイト読み取りを担当するヘルパークラス
  class PacketReader
    def initialize(client, timeout)
      @client = client
      @timeout = timeout
    end

    def read_exact(length)
      buffer = String.new
      remaining = length

      while remaining.positive?
        chunk = read_from_socket(remaining)
        buffer << chunk
        remaining -= chunk.bytesize
      end
      buffer
    end

    private

    def read_from_socket(limit)
      chunk = @client.read_nonblock(limit, exception: false)

      case chunk
      when :wait_readable then wait_and_retry(limit)
      when nil then raise InsufficientDataError, 'Connection closed'
      else chunk
      end
    end

    def wait_and_retry(limit)
      result = IO.select([@client], nil, nil, @timeout)
      raise Timeout::Error, "Read timeout after #{@timeout} seconds" if result.nil?

      read_from_socket(limit)
    end
  end
end
