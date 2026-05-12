# frozen_string_literal: true

require 'timeout'
require 'socket'

module RubyPureMysql
  class ProtocolError < StandardError; end
  class AuthenticationError < StandardError; end
  class InsufficientDataError < ProtocolError; end

  # 接続管理とコマンドのディスパッチをします。
  class Server
    MAX_PACKET_LEN = 0xFF_FF_FF
    READ_TIMEOUT = 5

    def initialize(port, host: '127.0.0.1')
      @server = TCPServer.new(host, port)
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
      puts "Unexpected error: #{e.class.name}: #{e.message}\n#{e.backtrace.join("\n")}"
      raise e
    end

    def authenticate(client, reader)
      write_handshake_v10(client)
      return false unless read_next_packet(reader)

      write_ok_packet(client)
      true
    end

    def command_phase_loop(client, reader)
      loop do
        payload, seq = read_next_packet(reader)
        break if payload.nil? || !dispatch_command(client, payload, seq)
      rescue InsufficientDataError
        break
      end
    end

    def dispatch_command(client, payload, seq)
      raise ProtocolError, 'empty command packet' if payload.empty?

      case payload.getbyte(0)
      when 0x01 then false # COM_QUIT
      when 0x03 then handle_query(client, payload[1..], seq)
      else
        write_err_packet(client, seq, "Unknown command: 0x#{payload.getbyte(0).to_s(16).upcase}")
        true
      end
    end

    def handle_query(client, sql, seq)
      if sql.strip.upcase.chomp(';') == 'SELECT 1'
        write_select_one_response(client, seq)
      else
        write_err_packet(client, seq, 'Unsupported query')
      end
      true
    end

    def read_next_packet(reader)
      header = reader.read_exact(4)
      return nil unless header

      len = header.unpack1('V') & 0xFFFFFF
      raise ProtocolError, "Invalid length: #{len}" if len <= 0
      raise ProtocolError, 'Multi-packet payloads are not supported' if len == MAX_PACKET_LEN

      [reader.read_exact(len), header.getbyte(3)]
    end

    # レスポンス送信系
    def write_select_one_response(client, seq)
      write_raw_packet(client, [1].pack('C'), seq + 1)
      write_raw_packet(client, col_def_payload, seq + 2)
      write_raw_packet(client, [0xfe, 0, 2].pack('Cvv'), seq + 3) # EOF
      write_raw_packet(client, "\x011", seq + 4) # Row Data ('1')
      write_raw_packet(client, [0xfe, 0, 2].pack('Cvv'), seq + 5) # EOF
    end

    def col_def_payload
      [
        "\x03def\x00\x00\x00\x011\x00\x0c",
        [33, 11, 8, 0, 0, 0].pack('vVCvCv')
      ].join
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
      write_raw_packet(client, [0x00, 0, 0, 2, 0].pack('CCCvv'), 2)
    end

    def write_err_packet(client, seq, message)
      payload = [0xFF, 1047, '#', '42000', message].pack('Cv a a5 a*')
      write_raw_packet(client, payload, seq + 1)
    end
  end

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
