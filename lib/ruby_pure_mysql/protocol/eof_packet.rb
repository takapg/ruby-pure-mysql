# frozen_string_literal: true

module RubyPureMysql
  module Protocol
    # EOF パケット (EOF_Packet)
    # サーバーからクライアントへ、一連のデータの終わりを告げるために送られます。
    # https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_basic_eof_packet.html
    class EofPacket < BasePacket
      # @param status_flags [Integer] サーバーの現在の状態
      # @param warnings [Integer] 警告の数
      def initialize(status_flags: SERVER_STATUS_AUTOCOMMIT, warnings: 0)
        super()
        unless warnings.is_a?(Integer) &&
               (0..0xFFFF).cover?(warnings) &&
               (0..0xFFFF).cover?(status_flags)
          raise ArgumentError, 'warnings and status_flags must be in 0..65535'
        end

        @status_flags = status_flags
        @warnings = warnings
      end

      # EOF パケットのペイロードを生成します。
      # 構造: Header(0xFE) + Warnings(2bytes) + StatusFlags(2bytes)
      def payload
        [
          [0xFE].pack('C'),           # Header (常に 0xFE)
          [@warnings].pack('v'),      # Warnings (2 bytes)
          [@status_flags].pack('v')   # Status Flags (2 bytes)
        ].join
      end
    end
  end
end
