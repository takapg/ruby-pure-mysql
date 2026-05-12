# frozen_string_literal: true

require 'securerandom'

module RubyPureMysql
  module Protocol
    # 接続開始時にサーバーからクライアントへ送られる Initial Handshake パケットです。
    # Protocol Revision 10 (MySQL 8.0/5.7等) に準拠します。
    class HandshakePacket < BasePacket
      # @param connection_id [Integer] この接続に割り振られた一意のID
      # @param auth_plugin_data [String] 認証に使用する20バイトのランダムデータ（省略時は自動生成）
      def initialize(connection_id: 1, auth_plugin_data: SecureRandom.random_bytes(20))
        super()
        validate_arguments!(connection_id, auth_plugin_data)

        auth_plugin_data = auth_plugin_data.b
        raise ArgumentError, 'auth_plugin_data must be exactly 20 bytes' unless auth_plugin_data.bytesize == 20

        @connection_id = connection_id
        @auth_plugin_data = auth_plugin_data
      end

      # Handshake V10 パケットのペイロードを生成します。
      def payload
        [
          header_part,
          auth_part1,
          capability_part,
          auth_part2
        ].join
      end

      private

      def validate_arguments!(connection_id, auth_plugin_data)
        unless connection_id.is_a?(Integer) && connection_id.between?(
          0, 0xFFFF_FFFF
        )
          raise ArgumentError,
                'connection_id must be an Integer between 0 and 4294967295'
        end
        return if auth_plugin_data.is_a?(String)

        raise ArgumentError,
              'auth_plugin_data must be a String of exactly 20 bytes'
      end

      def header_part
        [
          [10].pack('C'),                       # Protocol Version (常に10)
          pack_string_null('8.0.0-pure'),       # Server Version
          [@connection_id].pack('V')            # Connection ID
        ].join
      end

      def auth_part1
        auth_data_part1 = @auth_plugin_data.byteslice(0, 8)
        [
          pack_string_fixed(auth_data_part1, 8), # Auth-plugin-data-part-1
          [0].pack('C') # Filler (常に0)
        ].join
      end

      def capability_part
        [
          [DEFAULT_CAPABILITIES & 0xFFFF].pack('v'), # Capability Flags (Lower 2 bytes)
          [CHARSET_UTF8MB4].pack('C'),               # Character Set
          [SERVER_STATUS_AUTOCOMMIT].pack('v'),      # Status Flags
          [DEFAULT_CAPABILITIES >> 16].pack('v')     # Capability Flags (Upper 2 bytes)
        ].join
      end

      def auth_part2
        auth_data_part2 = @auth_plugin_data.byteslice(8, 12)
        [
          [21].pack('C'),                           # Auth-plugin-data-length (21 = 20 bytes + \0)
          pack_string_fixed('', 10),                # Reserved (すべて0)
          pack_string_fixed(auth_data_part2, 13),   # Auth-plugin-data-part-2 (+ \0)
          pack_string_null('mysql_native_password') # Auth-plugin-name
        ].join
      end
    end
  end
end
