# frozen_string_literal: true

require 'socket'
require 'timeout'

module RubyPureMysql
  # MySQL プロトコルのパケット単位での読み書き（フレーミング）と
  # バイナリデータのパース（ストリーム読み取り）を制御します。
  class PacketIO
    MAX_PACKET_LEN = 0xFF_FF_FF

    def initialize(client, timeout)
      @client = client
      @timeout = timeout
      @payload_buffer = +''
      @pos = 0
    end

    # --- パケットレベルの I/O ---

    def read_packet
      header = read_exact(4)
      return nil unless header

      len = (header.getbyte(0) | header.getbyte(1) << 8 | header.getbyte(2) << 16)
      seq = header.getbyte(3)

      raise ProtocolError, 'Multi-packet payloads are not supported' if len == MAX_PACKET_LEN

      # 新しいパケットをバッファにセットし、ポインタをリセット
      @payload_buffer = len.positive? ? read_exact(len) : +''
      @pos = 0
      [@payload_buffer, seq]
    end

    def write_packet(payload, seq)
      len = payload.bytesize
      raise ProtocolError, "Payload too large: #{len}" if len > MAX_PACKET_LEN

      # 3byte len + 1byte seq
      header = [len & 0xFF, (len >> 8) & 0xFF, (len >> 16) & 0xFF, seq % 256].pack('C4')
      @client.write(header + payload)
    end

    # --- バイナリパース（ストリーム読み取り）用メソッド ---

    def read_uint8
      raise ProtocolError, 'Buffer underflow' if @pos + 1 > @payload_buffer.bytesize

      val = @payload_buffer.getbyte(@pos)
      @pos += 1
      val
    end

    def read_uint16
      raise ProtocolError, 'Buffer underflow' if @pos + 2 > @payload_buffer.bytesize

      val = @payload_buffer.byteslice(@pos, 2).unpack1('v')
      @pos += 2
      val
    end

    def read_uint32
      raise ProtocolError, 'Buffer underflow' if @pos + 4 > @payload_buffer.bytesize

      val = @payload_buffer.byteslice(@pos, 4).unpack1('V')
      @pos += 4
      val
    end

    def read_string_null
      end_pos = @payload_buffer.index("\0", @pos)
      raise ProtocolError, 'Null terminator not found' unless end_pos

      str = @payload_buffer.byteslice(@pos, end_pos - @pos)
      @pos = end_pos + 1
      str
    end

    def read_string_eof
      str = @payload_buffer.byteslice(@pos..-1)
      @pos = @payload_buffer.bytesize
      str
    end

    # Length-Encoded Integer の読み取り
    def read_lenc_int
      first = read_uint8
      case first
      when 0..250 then first
      when 0xFB then nil
      when 0xFC then read_uint16
      when 0xFD then read_uint24_manual
      when 0xFE then read_uint64
      else raise ProtocolError, "Invalid lenc_int header: #{first}"
      end
    end

    private

    def read_uint24_manual
      raise ProtocolError, 'Buffer underflow' if @pos + 3 > @payload_buffer.bytesize

      data = @payload_buffer.byteslice(@pos, 3)
      @pos += 3
      (data.getbyte(0) | data.getbyte(1) << 8 | data.getbyte(2) << 16)
    end

    def read_uint64
      raise ProtocolError, 'Buffer underflow' if @pos + 8 > @payload_buffer.bytesize

      val = @payload_buffer.byteslice(@pos, 8).unpack1('Q<')
      @pos += 8
      val
    end

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
