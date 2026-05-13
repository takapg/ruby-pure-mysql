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
    # @param sql [String] 実行するSQL文字列
    def process(sql)
      # セミコロンの除去と正規化
      normalized_sql = sql.upcase.sub(/\s*;\s*\z/, '').strip

      # SELECT <数字> のパターンにマッチさせる
      if (match = normalized_sql.match(/\ASELECT\s+(\d+)\z/))
        # キャプチャした数字を文字列として取得
        value = match[1]
        write_integer_result_set(value)
      else
        write_err_packet("Unsupported query: #{sql[0..32]}...", '42000', 1047)
      end
    end

    private

    # 整数値を1つ返すResultSet（結果セット）を生成・送信します。
    # 構造: ColumnCount -> ColumnDefinition -> EOF -> RowData -> EOF
    # @param value [String] レスポンスとして返す数値の文字列
    def write_integer_result_set(value)
      # 1. Column Count (カラム数: 1)
      # 1バイトの整数としてパッキング
      @io.write_packet([1].pack('C'), @seq + 1)

      # 2. Column Definition (カラムのメタデータ)
      # カラム名を SELECT で指定された数値自体（例: "2"）に設定
      col_packet = Protocol::ColumnDefinitionPacket.new(
        name: value,
        column_type: Protocol::MYSQL_TYPE_LONG
      )
      @io.write_packet(col_packet.payload, @seq + 2)

      # 3. EOF (メタデータの終わり)
      eof_packet = Protocol::EofPacket.new
      @io.write_packet(eof_packet.payload, @seq + 3)

      # 4. Row Data (実際のデータ)
      # MySQLプロトコルでは、テキスト結果セットの各値は
      # Length-Encoded String としてエンコードして送信します。
      row_payload = PacketHelper.pack_lenc_string(value)
      @io.write_packet(row_payload, @seq + 4)

      # 5. EOF (結果セット全体の終わり)
      @io.write_packet(eof_packet.payload, @seq + 5)
    end

    # エラーパケットを生成して送信します。
    def write_err_packet(message, sql_state = '42000', error_code = 1047)
      # 構造: Header(0xFF) + ErrorCode(2) + SQLStateMarker('#') + SQLState(5) + Message
      payload = [0xFF, error_code, '#', sql_state, message].pack('Cv a a5 a*')
      @io.write_packet(payload, @seq + 1)
    end
  end
end
