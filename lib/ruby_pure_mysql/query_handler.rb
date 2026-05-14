# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの解釈と、それに対するレスポンスパケットの生成を担当します。
  class QueryHandler
    # MySQLの構文を模倣する正規表現
    # 数値、シングルクォート文字列、ダブルクォート文字列のいずれかを :val としてキャプチャ
    SELECT_PATTERN = /\ASELECT\s+(?:(?<val>\d+)|'(?<val>[^']*)'|"(?<val>[^"]*)")\z/i

    # @param io [PacketIO] パケットの送受信を行うオブジェクト
    # @param seq [Integer] クライアントから受け取った最後のシーケンス番号
    def initialize(io, seq)
      @io = io
      @seq = seq
    end

    # 受信したSQLクエリを解析し、適切なレスポンスを送信します。
    def process(sql)
      # セミコロンの除去と正規化
      normalized_sql = sql.sub(/\s*;\s*\z/, '').strip

      case normalized_sql
      when SELECT_PATTERN
        # 特殊変数 $~ (MatchData) から名前付きキャプチャを取得
        handle_select($~[:val])
      else
        write_err_packet("Unsupported query: #{sql[0..32]}...", '42000', 1047)
      end
    end

    private

    # SELECT クエリの結果（単一値）を送信
    def handle_select(value)
      # Text Resultset のフロー:
      # 1. Column Count (列数)
      # 2. Column Definition (列の定義)
      # 3. EOF Packet
      # 4. Row Data (実際のデータ)
      # 5. EOF Packet (結果セットの終了)
      
      write_column_count(1)
      write_column_definition(value)
      write_eof_packet(sequence_offset: 3) # カラム定義後のEOF
      write_row_data(value)
      write_eof_packet(sequence_offset: 5) # 全データ送信後のEOF
    end

    def write_column_count(count)
      @io.write_packet([count].pack('C'), @seq + 1)
    end

    def write_column_definition(name)
      # 文字列を返す可能性を考慮し、型はデフォルトで VAR_STRING (0xFD) に寄せるか、
      # あるいは既存の MYSQL_TYPE_LONG でも mysql2 側でよしなに処理されます。
      col_packet = Protocol::ColumnDefinitionPacket.new(
        name: name.to_s,
        column_type: Protocol::MYSQL_TYPE_LONG
      )
      @io.write_packet(col_packet.payload, @seq + 2)
    end

    def write_row_data(value)
      # MySQLプロトコルの行データは、各カラム値を Length-Encoded String として連結したもの
      row_payload = PacketHelper.pack_lenc_string(value.to_s)
      @io.write_packet(row_payload, @seq + 4)
    end

    # sequence_offset を引数に取ることで、どの段階のEOFかを明示的に制御
    def write_eof_packet(sequence_offset:)
      @io.write_packet(Protocol::EofPacket.new.payload, @seq + sequence_offset)
    end

    def write_err_packet(message, sql_state = '42000', error_code = 1047)
      payload = [0xFF, error_code, '#', sql_state, message].pack('Cv a a5 a*')
      @io.write_packet(payload, @seq + 1)
    end
  end
end
