# frozen_string_literal: true

module RubyPureMysql
  module Protocol
    # 接続開始時にサーバーからクライアントへ送られる Initial Handshake パケットです。
    # Protocol Revision 10 (MySQL 8.0/5.7等) に準拠します。
    class HandshakePacket < BasePacket
      # @param connection_id [Integer] この接続に割り振られた一意のID
      # @param auth_plugin_data [String] 認証に使用する20バイトのランダムデータ
      def initialize(connection_id: 1, auth_plugin_data: '12345678901234567890')
        @connection_id = connection_id
        @auth_plugin_data = auth_plugin_data
      end

      # Handshake V10 パケットのペイロードを生成します。
      def payload
        # 認証データの分割 (MySQLプロトコルの仕様で、8バイトと12バイトに分けて格納します)
        auth_data_part1 = @auth_plugin_data[0, 8]
        auth_data_part2 = @auth_plugin_data[8, 12]

        [
          [10].pack('C'),                       # Protocol Version (常に10)
          pack_string_null('8.0.0-pure'),       # Server Version
          [@connection_id].pack('V'),           # Connection ID
          pack_string_fixed(auth_data_part1, 8), # Auth-plugin-data-part-1
          [0].pack('C'),                        # Filler (常に0)
          pack_int3(DEFAULT_CAPABILITIES & 0xFFFF), # Capability Flags (Lower 2 bytes)
          [CHARSET_UTF8MB4].pack('C'),          # Character Set
          [SERVER_STATUS_AUTOCOMMIT].pack('v'), # Status Flags
          [(DEFAULT_CAPABILITIES >> 16)].pack('v'), # Capability Flags (Upper 2 bytes)
          [21].pack('C'),                       # Auth-plugin-data-length (21 = 20 bytes + \0)
          pack_string_fixed('', 10),            # Reserved (すべて0)
          pack_string_fixed(auth_data_part2, 13), # Auth-plugin-data-part-2 (+ \0)
          pack_string_null('mysql_native_password') # Auth-plugin-name
        ].join
      end
    end
  end
end
