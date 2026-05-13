# frozen_string_literal: true

module RubyPureMysql
  # パケットのペイロード（バイナリ）を順次読み取るためのクラスです。
  # 内部で読み取り位置（pos）を保持し、各種データ型を抽出します。
  class PacketReader
    def initialize(payload)
      @payload = payload
      @pos = 0
    end

    # 1バイト（uint8）読み取ります。
    def read_uint8
      raise ProtocolError, 'Buffer underflow' if @pos + 1 > @payload.bytesize

      val = @payload.getbyte(@pos)
      @pos += 1
      val
    end

    # 2バイト（uint16）読み取ります。
    def read_uint16
      raise ProtocolError, 'Buffer underflow' if @pos + 2 > @payload.bytesize

      val = @payload.byteslice(@pos, 2).unpack1('v')
      @pos += 2
      val
    end

    # 4バイト（uint32）読み取ります。
    def read_uint32
      raise ProtocolError, 'Buffer underflow' if @pos + 4 > @payload.bytesize

      val = @payload.byteslice(@pos, 4).unpack1('V')
      @pos += 4
      val
    end

    # Null終端文字列を読み取ります。
    def read_string_null
      end_pos = @payload.index("\0", @pos)
      raise ProtocolError, 'Null terminator not found' unless end_pos

      str = @payload.byteslice(@pos, end_pos - @pos)
      @pos = end_pos + 1
      str
    end

    # 残りの全データを文字列として読み取ります。
    def read_string_eof
      str = @payload.byteslice(@pos..-1)
      @pos = @payload.bytesize
      str
    end

    # Length-Encoded Integer を読み取ります。
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
      raise ProtocolError, 'Buffer underflow' if @pos + 3 > @payload.bytesize

      data = @payload.byteslice(@pos, 3)
      @pos += 3
      (data.getbyte(0) | data.getbyte(1) << 8 | data.getbyte(2) << 16)
    end

    def read_uint64
      raise ProtocolError, 'Buffer underflow' if @pos + 8 > @payload.bytesize

      val = @payload.byteslice(@pos, 8).unpack1('Q<')
      @pos += 8
      val
    end
  end
end
