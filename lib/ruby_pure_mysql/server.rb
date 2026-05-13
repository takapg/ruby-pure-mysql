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
    end

    def authenticate(io)
      # サーバーからの Handshake 送信
      handshake = Protocol::HandshakePacket.new(connection_id: 1)
      io.write_packet(handshake.payload, 0)

      # クライアントからの HandshakeResponse 受信
      # 本来はここで io.read_uint32 (capability) などを呼び出して認証情報を検証する
      payload, seq = io.read_packet
      return false unless payload

      # 現状は Password-less として常に OK を返す
      ok_packet = Protocol::OkPacket.new
      io.write_packet(ok_packet.payload, seq + 1)
      true
    rescue InsufficientDataError
      false
    end

    def command_phase_loop(io)
      loop do
        # パケットの読み込み（ここで PacketIO 内部のバッファが更新される）
        payload, seq = io.read_packet
        break if payload.nil?

        # コマンドのディスパッチを実行。false が返ればループ終了（切断）
        break unless dispatch_command(io, seq)
      rescue InsufficientDataError
        break
      end
    end

    def dispatch_command(io, seq)
      # 先頭1バイトを読み取ってコマンドを判定
      command = io.read_uint8

      case command
      when Protocol::COM_QUIT then false
      when Protocol::COM_QUERY
        handle_query(io, io.read_string_eof, seq)
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
      write_err_packet(io, seq, "Internal Server Error: #{e.message}")
    end

    def write_err_packet(io, seq, message)
      # ERR_Packet の簡易実装: header(0xFF) + error_code(2) + sql_state_marker(#) + sql_state(5) + message
      payload = [0xFF, 1047, '#', '42000', message].pack('Cv a a5 a*')
      io.write_packet(payload, seq + 1)
    end
  end
end
