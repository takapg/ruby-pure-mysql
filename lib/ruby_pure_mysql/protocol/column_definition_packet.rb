# frozen_string_literal: true

module RubyPureMysql
  module Protocol
    # Column Definition パケット (ColumnDefinitionPacket)
    # クエリ結果のメタデータをクライアントに伝えます。
    # https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_com_query_response_text_resultset_column_definition.html
    class ColumnDefinitionPacket < BasePacket
      # @param name [String] カラム名
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
          string_metadata,
          [0x0C].pack('C'), # length of fixed-length fields
          [@character_set, @column_length].pack('vV'), # character_set (2b), column_length (4b)
          [@column_type, 0x0000, 0x00, 0x0000].pack('CvCv') # type (1b), flags (2b), decimals (1b), filler (2b)
        ].join
      end

      private

      # 文字列ベースのメタデータをまとめます。
      # 構造: catalog ("def"), schema, table, org_table, name, org_name
      def string_metadata
        ['def', '', '', '', @name, @name].map { |s| pack_lenc_string(s) }.join
      end
    end
  end
end
