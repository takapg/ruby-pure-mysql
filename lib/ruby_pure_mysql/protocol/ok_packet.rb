# frozen_string_literal: true

module RubyPureMysql
  module Protocol
    # OK パケット (OK_Packet)
    # サーバーからクライアントへ、コマンドの成功を知らせるために送られます。
    # https://dev.mysql.com/doc/dev/mysql-server/latest/page_protocol_basic_ok_packet.html
    class OkPacket < BasePacket
      def initialize(affected_rows: 0, last_insert_id: 0, status_flags: SERVER_STATUS_AUTOCOMMIT, warnings: 0)
        super()
        @affected_rows = affected_rows
        @last_insert_id = last_insert_id
        @status_flags = status_flags
        @warnings = warnings
      end

      # OK パケットのペイロードを生成します。
      def payload
        [
          [0x00].pack('C'),                       # Header (常に 0)
          pack_lenc_int(@affected_rows),          # Affected Rows
          pack_lenc_int(@last_insert_id),         # Last Insert ID
          [@status_flags].pack('v'),              # Status Flags
          [@warnings].pack('v')                   # Warnings
        ].join
      end
    end
  end
end
