# frozen_string_literal: true

require 'English'

module RubyPureMysql
  # SQLクエリの解釈と、それに対するレスポンスパケットの生成を担当します。
  class QueryHandler
    # 抽出用正規表現
    # expr: カラム名として使用する全体式
    # num: 数値リテラル
    # str: クォート内の文字列
    SELECT_PATTERN = /\ASELECT\s+(?<expr>(?:(?<num>\d+)|'(?<str>[^']*)'|"(?<str>[^"]*)"))\z/i

    # 数値範囲の定義
    INT32_MAX = 2_147_483_647
    INT32_MIN = -2_147_483_648

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
        # CodeRabbit指摘: SELECT "" 等の時に列名が "?" にならないよう、マッチした式をそのまま使う
        column_name = match[:expr]

        if match[:num]
          # CodeRabbit指摘: 数値の大きさに応じて LONG(32bit) か LONGLONG(64bit) を選択
          val_i = match[:num].to_i
          type = (val_i > INT32_MAX || val_i < INT32_MIN) ? Protocol::MYSQL_TYPE_LONGLONG : Protocol::MYSQL_TYPE_LONG
          handle_select(match[:num], type, column_name)
        else
          handle_select(match[:str], Protocol::MYSQL_TYPE_VAR_STRING, column_name)
        end
      else
        write_err_packet("Unsupported or invalid query: #{sql[0..32]}...", '42000', 1064)
      end
    end

    private

    # SELECT クエリの結果を送信します。
    def handle_select(value, type, column_name)
      write_column_count(1)
      write_column_definition(column_name, type)
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
        column_type: type
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
