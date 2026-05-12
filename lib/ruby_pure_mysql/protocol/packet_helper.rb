# frozen_string_literal: true

module RubyPureMysql
  # MySQL プロトコル固有のデータパッキング・アンパッキングを助けるモジュールです。
  module PacketHelper
    module_function

    # 3バイトリトルエンディアン整数をパッキングします。
    # MySQL のパケット長ヘッダなどで多用されます。
    def pack_int3(n)
      [n].pack('V')[0, 3]
    end

    # 3バイトリトルエンディアン整数をアンパッキングします。
    def unpack_int3(data)
      "#{data}\u0000".unpack1('V')
    end

    # Length-Encoded Integer (LEI) をパッキングします。
    # https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_basic_dt_integers.html#sect_protocol_basic_dt_integers_field_length_encoded_int
    def pack_lenc_int(n)
      if n < 251
        [n].pack('C')
      elsif n < 0x10000
        "\xFC#{[n].pack('v')}"
      elsif n < 0x1000000
        "\xFD#{pack_int3(n)}"
      else
        "\xFE#{[n].pack('Q<')}"
      end
    end

    # Null-Terminated String (文字列 + \0) を作成します。
    def pack_string_null(str)
      "#{str}\0"
    end

    # 固定長の文字列を作成します。
    def pack_string_fixed(str, len)
      [str].pack("a#{len}")
    end

    # Length-Encoded String を作成します。
    def pack_lenc_string(str)
      return "\xFB" if str.nil?

      pack_lenc_int(str.bytesize) + str
    end
  end
end
