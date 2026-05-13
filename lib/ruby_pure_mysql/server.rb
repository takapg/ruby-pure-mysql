# frozen_string_literal: true

module RubyPureMysql
  # 接続管理とコマンドのディスパッチをします。
  class Server
    MAX_PACKET_LEN = 0xFF_FF_FF
    READ_TIMEOUT = 5

    def initialize(host: '127.0.0.1', port: 3307)
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
      io = PacketIO.new(client, READ_TIMEOUT)
      return unless authenticate(io)

      command_phase_loop(io)
    rescue StandardError => e
      puts "Unexpected error: #{e.class.name}: #{e.message}\n#{e.backtrace.join("\n")}"
      raise e
    end

    def authenticate(io)
      handshake_packet = Protocol::HandshakePacket.new(connection_id: 1)
      io.write_packet(handshake_packet.payload, 0)

      auth_packet = io.read_packet
      return false unless auth_packet

      _auth_payload, auth_seq = auth_packet
      ok_packet = Protocol::OkPacket.new
      io.write_packet(ok_packet.payload, auth_seq + 1)
      true
    rescue InsufficientDataError
      false
    end

    def command_phase_loop(io)
      loop do
        payload, seq = io.read_packet
        break if payload.nil? || !dispatch_command(io, payload, seq)
      rescue InsufficientDataError
        break
      end
    end

    def dispatch_command(io, payload, seq)
      raise ProtocolError, 'empty command packet' if payload.empty?

      case payload.getbyte(0)
      when Protocol::COM_QUIT  then false
      when Protocol::COM_QUERY then handle_query(io, payload[1..], seq)
      else
        write_err_packet(io, seq, "Unknown command: 0x#{payload.getbyte(0).to_s(16).upcase}")
        true
      end
    end

    def handle_query(io, sql, seq)
      QueryHandler.new(io, seq).process(sql)
      true
    rescue StandardError => e
      puts "Unexpected error during query: #{e.class}: #{e.message}"
      write_err_packet(io, seq, "Internal Server Error: #{e.class}")
      true
    end

    def write_err_packet(io, seq, message)
      payload = [0xFF, 1047, '#', '42000', message].pack('Cv a a5 a*')
      io.write_packet(payload, seq + 1)
    end
  end
end
