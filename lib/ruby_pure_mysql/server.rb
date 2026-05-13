# frozen_string_literal: true

require 'socket'

module RubyPureMysql
  # 接続管理とコマンドのディスパッチを担当します。
  class Server
    READ_TIMEOUT = 5

    def initialize(host: '127.0.0.1', port: 3307)
      @server = TCPServer.new(host, port)
    end

    def run
      loop do
        client = @server.accept
        handle_client(client)
      rescue ProtocolError, AuthenticationError, Timeout::Error, Errno::ECONNRESET, Errno::EPIPE => e
        puts "Expected connection error: #{e.class.name}: #{e.message}"
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
      handshake = Protocol::HandshakePacket.new(connection_id: 1)
      io.write_packet(handshake.payload, 0)

      # 修正点: payload ではなく reader が返る
      reader, seq = io.read_packet
      return false unless reader

      # 本来は reader.read_uint32 などで中身を検証する
      ok_packet = Protocol::OkPacket.new
      io.write_packet(ok_packet.payload, seq + 1)
      true
    rescue InsufficientDataError
      false
    end

    def command_phase_loop(io)
      loop do
        reader, seq = io.read_packet # 修正点: payload -> reader
        break if reader.nil?

        break unless dispatch_command(io, reader, seq) # 修正点: readerを渡す
      rescue InsufficientDataError
        break
      end
    end

    def dispatch_command(io, reader, seq) # 修正点: 引数に reader を追加
      command = reader.read_uint8 # 修正点: reader から読み取る
      return handle_unknown_command(io, 0, seq) unless command

      case command
      when Protocol::COM_QUIT then false
      when Protocol::COM_QUERY
        handle_query(io, reader.read_string_eof, seq) # 修正点: reader から読み取る
        true
      else
        handle_unknown_command(io, command, seq)
      end
    end

    def handle_unknown_command(io, command, seq)
      write_err_packet(io, seq, "Unknown command: 0x#{command.to_s(16).upcase}")
      true
    end

    def handle_query(io, sql, seq)
      QueryHandler.new(io, seq).process(sql)
    rescue StandardError => e
      puts "Query Error: #{e.class}: #{e.message}"
      write_err_packet(io, seq, 'Internal Server Error')
    end

    def write_err_packet(io, seq, message)
      payload = [0xFF, 1047, '#', '42000', message].pack('Cv a a5 a*')
      io.write_packet(payload, seq + 1)
    end
  end
end
