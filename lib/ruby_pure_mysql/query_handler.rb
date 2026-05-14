# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの解釈と、それに対するレスポンスパケットの生成を担当します。
  class QueryHandler
    # 抽出用正規表現。名前付きキャプチャを使用して可読性を維持。
    SELECT_PATTERN = /\ASELECT\s+(?<expr>(?:(?<num>\d+)|'(?<str>[^']*)'|"(?<str>[^"]*)"))\z/i

    # 数値範囲の定義
    INT32_RANGE = (-2_147_483_648..2_147_483_647)

    def initialize(io, seq)
      @io = io
      @seq = seq
    end

    # 受信したSQLクエリを解析し、適切なレスポンスを送信します。
    def process(sql)
      # 修正: gsub と strip で末尾の全セミコロンと空白を確実に除去
      normalized = sql.gsub(/[;\s]+\z/, '').strip

      if (match = normalized.match(SELECT_PATTERN))
        handle_matched_query(match)
      else
        write_err_packet("Unsupported or invalid query: #{sql[0..32]}...", '42000', 1064)
      end
    end

    private

    # process メソッドを分割して Metrics/MethodLength を回避
    def handle_matched_query(match)
      if match[:num]
        val_i = match[:num].to_i
        type = INT32_RANGE.cover?(val_i) ? Protocol::MYSQL_TYPE_LONG : Protocol::MYSQL_TYPE_LONGLONG
        handle_select(match[:num], type, match[:expr])
      else
        handle_select(match[:str], Protocol::MYSQL_TYPE_VAR_STRING, match[:expr])
      end
    end

    # SELECT クエリの結果を送信
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
        name: name.to_s, column_type: type
      )
      @io.write_packet(col_packet.payload, @seq + 2)
    end

    def write_row_data(value)
      @io.write_packet(PacketHelper.pack_lenc_string(value.to_s), @seq + 4)
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
