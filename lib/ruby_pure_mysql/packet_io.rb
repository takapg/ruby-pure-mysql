# frozen_string_literal: true

require 'socket'
require 'timeout'

module RubyPureMysql
  # MySQL プロトコルのパケット単位での読み書き（フレーミング）を制御します。
  # 実際のペイロード解析は PacketReader に委ねます。
  class PacketIO
    MAX_PACKET_LEN = 0xFF_FF_FF

    def initialize(client, timeout)
      @client = client
      @timeout = timeout
    end

    # パケットを読み取り、PacketReader オブジェクトとシーケンス番号を返します。
    # @return [Array(PacketReader, Integer)]
    def read_packet
      header = read_exact(4)

      len = (header.getbyte(0) | header.getbyte(1) << 8 | header.getbyte(2) << 16)
      seq = header.getbyte(3)

      raise ProtocolError, 'Multi-packet payloads are not supported' if len == MAX_PACKET_LEN

      payload = len.positive? ? read_exact(len) : +''
      [PacketReader.new(payload), seq]
    end

    # ペイロードをパケットとして送信します。
    def write_packet(payload, seq)
      len = payload.bytesize
      raise ProtocolError, "Payload too large: #{len}" if len > MAX_PACKET_LEN

      # 3byte len + 1byte seq
      header = [len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF, seq % 256].pack('C4')
      @client.write(header + payload)
    end

    private

    def read_exact(length)
      buffer = +''
      while buffer.bytesize < length
        remaining = length - buffer.bytesize
        chunk = read_from_socket(remaining)
        break unless chunk

        buffer << chunk
      end
      raise InsufficientDataError, 'Connection closed' if buffer.bytesize < length

      buffer
    end

    def read_from_socket(length)
      loop do
        case (chunk = @client.read_nonblock(length, exception: false))
        when :wait_readable then wait_socket
        when nil then return nil
        else return chunk
        end
      end
    end

    def wait_socket
      result = IO.select([@client], nil, nil, @timeout)
      raise Timeout::Error, 'Read timeout' if result.nil?
    end
  end
end
