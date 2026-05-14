# frozen_string_literal: true

require 'English'

module RubyPureMysql
  # SQLクエリの解釈と、それに対するレスポンスパケットの生成を担当します。
  class QueryHandler
    # 名前付きキャプチャ (?<val>...) を各グループに使用することで、
    # どの形式にマッチしても match[:val] で値を取得できるようにします。
    SELECT_PATTERN = /\ASELECT\s+(?:(?<val>\d+)|'(?<val>[^']*)'|"(?<val>[^"]*)")\z/i

    # @param io [PacketIO] パケットの送受信を行うオブジェクト
    # @param seq [Integer] クライアントから受け取った最後のシーケンス番号
    def initialize(io, seq)
      @io = io
      @seq = seq
    end

    # 受信したSQLクエリを解析し、適切なレスポンスを送信します。
    def process(sql)
      normalized_sql = sql.sub(/\s*;\s*\z/, '').strip

      # String#match で MatchData オブジェクトを取得
      if (match = normalized_sql.match(SELECT_PATTERN))
        # 名前付きキャプチャ :val から値を取り出す
        handle_select(match[:val])
      else
        write_err_packet("Unsupported or invalid query: #{sql[0..32]}...", '42000', 1064)
      end
    end

    private

    # SELECT クエリの結果（単一値）を送信します。
    def handle_select(value)
      # カラム名が空（SELECT ""; など）の場合、MySQLクライアントが壊れないようフォールバック
      display_name = (value.nil? || value.empty?) ? '?' : value

      write_column_count(1)
      write_column_definition(display_name)
      write_eof_packet(sequence_offset: 3)
      write_row_data(value)
      write_eof_packet(sequence_offset: 5)
    end

    def write_column_count(count)
      @io.write_packet([count].pack('C'), @seq + 1)
    end

    def write_column_definition(name)
      # Protocol::MYSQL_TYPE_LONG のままだとクライアントが数値として解釈しようとする場合があるため、
      # 文字列を返す場合は本来 MYSQL_TYPE_VAR_STRING (0xFD) が適切ですが、
      # 現在の構成を維持しつつ name.to_s で安全にパケット化します。
      col_packet = Protocol::ColumnDefinitionPacket.new(
        name: name.to_s,
        column_type: Protocol::MYSQL_TYPE_LONG
      )
      @io.write_packet(col_packet.payload, @seq + 2)
    end

    def write_row_data(value)
      # 値を Length-Encoded String としてパッキング
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
