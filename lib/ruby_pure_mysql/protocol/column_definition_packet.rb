# frozen_string_literal: true

module RubyPureMysql
  module Protocol
    # Column Definition パケット (ColumnDefinitionPacket)
    # クエリ結果のメタデータをクライアントに伝えます。
    # https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_com_query_response_text_resultset_column_definition.html
    class ColumnDefinitionPacket < BasePacket
      # @param name [String] カラム名
      # @param column_type [Integer] カラムのデータ型（MYSQL_TYPE_VAR_STRING など）
      # @param character_set [Integer] 文字セット ID
      # @param column_length [Integer] カラムの最大表示幅
      def initialize(name:, column_type: 0xFD, character_set: CHARSET_UTF8MB4, column_length: 255)
        super()
        @name = name
        @column_type = column_type
        @character_set = character_set
        @column_length = column_length
      end

      # Column Definition パケットのペイロードを生成します。
      def payload
        [
          pack_lenc_string('def'),              # catalog (常に "def")
          pack_lenc_string(''),                 # schema
          pack_lenc_string(''),                 # table
          pack_lenc_string(''),                 # org_table
          pack_lenc_string(@name),              # name
          pack_lenc_string(@name),              # org_name
          pack_lenc_int(0x0C),                  # length of fixed-length fields (常に 0x0C)
          [@character_set].pack('v'),           # character_set (2 bytes)
          [@column_length].pack('V'),           # column_length (4 bytes)
          [@column_type].pack('C'),             # column_type (1 byte)
          [0x0000].pack('v'),                   # flags (2 bytes)
          [0x00].pack('C'),                     # decimals (1 byte)
          [0x0000].pack('v')                    # filler (2 bytes)
        ].join
      end
    end
  end
end
