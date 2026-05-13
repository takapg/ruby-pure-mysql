# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの解釈と、それに対するレスポンスパケットの生成を担当します。
  class QueryHandler
    # @param io [PacketIO] パケットの送受信を行うオブジェクト
    # @param seq [Integer] クライアントから受け取った最後のシーケンス番号
    def initialize(io, seq)
      @io = io
      @seq = seq
    end

    # 受信したSQLクエリを解析し、適切なレスポンスを送信します。
    def process(sql)
      normalized_sql = sql.upcase.sub(/\s*;\s*\z/, '').strip

      if (match = normalized_sql.match(/\ASELECT\s+(\d+)\z/))
        write_integer_result_set(match[1])
      else
        write_err_packet("Unsupported query: #{sql[0..32]}...", '42000', 1047)
      end
    end

    private

    # 整数値を1つ返すResultSetを生成・送信します。
    def write_integer_result_set(value)
      write_column_count(1)
      write_column_definition(value)
      write_eof_packet(2)
      write_row_data(value)
      write_eof_packet(4)
    end

    def write_column_count(count)
      @io.write_packet([count].pack('C'), @seq + 1)
    end

    def write_column_definition(name)
      col_packet = Protocol::ColumnDefinitionPacket.new(
        name: name,
        column_type: Protocol::MYSQL_TYPE_LONG
      )
      @io.write_packet(col_packet.payload, @seq + 2)
    end

    def write_row_data(value)
      row_payload = PacketHelper.pack_lenc_string(value)
      @io.write_packet(row_payload, @seq + 4)
    end

    def write_eof_packet(offset)
      @io.write_packet(Protocol::EofPacket.new.payload, @seq + 1 + offset)
    end

    def write_err_packet(message, sql_state = '42000', error_code = 1047)
      payload = [0xFF, error_code, '#', sql_state, message].pack('Cv a a5 a*')
      @io.write_packet(payload, @seq + 1)
    end
  end
end
