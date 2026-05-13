# frozen_string_literal: true

module RubyPureMysql
  # SQLクエリの解釈と、それに対するレスポンスパケットの生成を担当します。
  # サーバー本体（Server）から「何を返すか」のロジックを切り離すためのクラスです。
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
      normalized_sql = sql.strip.upcase.chomp(';')

      case normalized_sql
      when 'SELECT 1'
        write_select_one_response
      else
        write_err_packet("Unsupported query: #{sql[0..32]}...", '42000', 1047)
      end
    end

    private

    # 'SELECT 1' に対する MySQL 互換のレスポンス（ResultSet）を生成・送信します。
    # 構造: ColumnCount -> ColumnDefinition -> EOF -> RowData -> EOF
    def write_select_one_response
      col_packet = Protocol::ColumnDefinitionPacket.new(
        name: '1',
        column_type: Protocol::MYSQL_TYPE_LONG
      )
      eof_packet = Protocol::EofPacket.new

      # 1. Column Count (カラム数: 1)
      @io.write_packet([1].pack('C'), @seq + 1)

      # 2. Column Definition (カラムのメタデータ)
      @io.write_packet(col_packet.payload, @seq + 2)

      # 3. EOF (メタデータの終わり)
      @io.write_packet(eof_packet.payload, @seq + 3)

      # 4. Row Data (実際のデータ: "1")
      # 文字列としてエンコードされた値（\x01 は長さ1）を送信
      @io.write_packet("\x011", @seq + 4)

      # 5. EOF (結果セットの終わり)
      @io.write_packet(eof_packet.payload, @seq + 5)
    end

    # エラーパケットを生成して送信します。
    # @param message [String] エラーメッセージ
    # @param sql_state [String] 5文字のSQLステートコード
    # @param error_code [Integer] MySQLエラー番号
    def write_err_packet(message, sql_state = '42000', error_code = 1047)
      # 構造: Header(0xFF) + ErrorCode(2) + SQLStateMarker('#') + SQLState(5) + Message
      payload = [0xFF, error_code, '#', sql_state, message].pack('Cv a a5 a*')
      @io.write_packet(payload, @seq + 1)
    end
  end
end
