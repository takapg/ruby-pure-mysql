# frozen_string_literal: true

module RubyPureMysql
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
      handshake_packet = Protocol::HandshakePacket.new(connection_id: 1)
      write_raw_packet(client, handshake_packet.payload, 0)

      auth_packet = read_next_packet(reader)
      return false unless auth_packet

      _auth_payload, auth_seq = auth_packet
      ok_packet = Protocol::OkPacket.new
      write_raw_packet(client, ok_packet.payload, auth_seq + 1)
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
      when Protocol::COM_QUIT  then false
      when Protocol::COM_QUERY then handle_query(client, payload[1..], seq)
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
      col_packet = Protocol::ColumnDefinitionPacket.new(name: '1', column_type: Protocol::MYSQL_TYPE_LONG)
      eof_packet = Protocol::EofPacket.new

      write_raw_packet(client, [1].pack('C'), seq + 1)
      write_raw_packet(client, col_packet.payload, seq + 2)
      write_raw_packet(client, eof_packet.payload, seq + 3)
      write_raw_packet(client, "\x011", seq + 4) # Row Data ('1')
      write_raw_packet(client, eof_packet.payload, seq + 5)
    end

    def write_raw_packet(client, payload, seq)
      header = [payload.bytesize].pack('V')[0, 3] + [seq % 256].pack('C')
      client.write(header + payload)
    end

    def write_err_packet(client, seq, message)
      payload = [0xFF, 1047, '#', '42000', message].pack('Cv a a5 a*')
      write_raw_packet(client, payload, seq + 1)
    end
  end
end
