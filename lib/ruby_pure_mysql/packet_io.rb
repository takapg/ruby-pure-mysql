# frozen_string_literal: true

require 'socket'
require 'timeout'

module RubyPureMysql
  # MySQL プロトコルのパケット単位での読み書き（フレーミング）を制御します。
  class PacketIO
    MAX_PACKET_LEN = 0xFF_FF_FF

    def initialize(client, timeout)
      @client = client
      @timeout = timeout
    end

    def read_packet
      header = read_exact(4)
      return nil unless header

      len = header.unpack1('V') & 0xFFFFFF
      seq = header.getbyte(3)

      raise ProtocolError, "Invalid packet length: #{len}" if len <= 0
      raise ProtocolError, 'Multi-packet payloads are not supported' if len == MAX_PACKET_LEN

      [read_exact(len), seq]
    end

    def write_packet(payload, seq)
      len = payload.bytesize
      raise ProtocolError, "Payload too large: #{len}" if len > MAX_PACKET_LEN
      header = [len].pack('V')[0, 3] + [seq % 256].pack('C')
      @client.write(header + payload)
    end

    private

    # 指定されたバイト数に達するまで読み取ります。
    def read_exact(length)
      buffer = +''
      while buffer.bytesize < length
        remaining = length - buffer.bytesize
        chunk = read_from_socket(remaining)
        break unless chunk

        buffer << chunk
      end
      buffer.bytesize == length ? buffer : nil
    end

    # ノンブロッキングでソケットから読み取り、待機処理をハンドルします。
    def read_from_socket(length)
      case (chunk = @client.read_nonblock(length, exception: false))
      when :wait_readable
        wait_socket
        read_from_socket(length) # 再試行
      when nil
        raise InsufficientDataError, 'Connection closed by peer'
      else
        chunk
      end
    end

    def wait_socket
      result = IO.select([@client], nil, nil, @timeout)
      raise Timeout::Error, 'Read timeout' if result.nil?
    end
  end
end
