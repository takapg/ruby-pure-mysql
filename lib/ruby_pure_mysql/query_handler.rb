# frozen_string_literal: true

require 'English'

module RubyPureMysql
  # SQLクエリの解釈と、それに対するレスポンスパケットの生成を担当します。
  class QueryHandler
    SELECT_PATTERN = /\ASELECT\s+(?:(?<num>\d+)|'(?<str>[^']*)'|"(?<str>[^"]*)")\z/i

    # MySQL プロトコル上の型定義（もし constants.rb になければこちらを使用）
    MYSQL_TYPE_LONG = 0x03
    MYSQL_TYPE_VAR_STRING = 0xfd

    # @param io [PacketIO] パケットの送受信を行うオブジェクト
    # @param seq [Integer] クライアントから受け取った最後のシーケンス番号
    def initialize(io, seq)
      @io = io
      @seq = seq
    end

    # 受信したSQLクエリを解析し、適切なレスポンスを送信します。
    def process(sql)
      normalized_sql = sql.sub(/\s*;\s*\z/, '').strip

      if (match = normalized_sql.match(SELECT_PATTERN))
        if match[:num]
          # 数値としてマッチした場合
          handle_select(match[:num], MYSQL_TYPE_LONG)
        else
          # 文字列（クォートあり）としてマッチした場合
          handle_select(match[:str], MYSQL_TYPE_VAR_STRING)
        end
      else
        write_err_packet("Unsupported or invalid query: #{sql[0..32]}...", '42000', 1064)
      end
    end

    private

    # SELECT クエリの結果を送信します。
    # @param value [String] 送信する値
    # @param type [Integer] MySQLのフィールド型
    def handle_select(value, type)
      display_name = value.nil? || value.empty? ? '?' : value

      write_column_count(1)
      write_column_definition(display_name, type)
      write_eof_packet(sequence_offset: 3)
      write_row_data(value)
      write_eof_packet(sequence_offset: 5)
    end

    def write_column_count(count)
      @io.write_packet([count].pack('C'), @seq + 1)
    end

    def write_column_definition(name, type)
      col_packet = Protocol::ColumnDefinitionPacket.new(
        name: name.to_s,
        column_type: type # 判別した型（LONG または VAR_STRING）を渡す
      )
      @io.write_packet(col_packet.payload, @seq + 2)
    end

    def write_row_data(value)
      row_payload = PacketHelper.pack_lenc_string(value.to_s)
      @io.write_packet(row_payload, @seq + 4)
    end

    def write_eof_packet(sequence_offset:)
      @io.write_packet(Protocol::EofPacket.new.payload, @seq + sequence_offset)
    end

    def write_err_packet(message, sql_state = '42000', error_code = 1047)
      payload = [0xFF, error_code, '#', sql_state, message].pack('Cv a a5 a*')
      @io.write_packet(payload, @seq + 1)
    end
  end
end
