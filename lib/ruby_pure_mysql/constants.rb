# frozen_string_literal: true

module RubyPureMysql
  # MySQL プロトコルで使用される共通の定数定義です。
  module Protocol
    # コマンド型 (Command Phase)
    COM_QUIT  = 0x01
    COM_QUERY = 0x03

    # カラム型 (Field Types)
    MYSQL_TYPE_LONG       = 0x03
    MYSQL_TYPE_LONGLONG   = 0x08
    MYSQL_TYPE_VAR_STRING = 0xfd

    # キャラクターセット
    # 45 は utf8mb4_general_ci を指します。
    CHARSET_UTF8MB4 = 45

    # サーバーのステータスフラグ (Status Flags)
    # クライアントに現在のトランザクション状態などを伝えます。
    SERVER_STATUS_AUTOCOMMIT = 0x0002

    # ケイパビリティフラグ (Capability Flags)
    # サーバーとクライアントの間で「どの機能が使えるか」を合意するために使います。
    # 以下の値は最低限必要なフラグを組み合わせたものです。
    CLIENT_LONG_PASSWORD     = 0x0001
    CLIENT_FOUND_ROWS        = 0x0002
    CLIENT_LONG_FLAG         = 0x0004
    CLIENT_CONNECT_WITH_DB   = 0x0008
    CLIENT_PROTOCOL_41       = 0x0200
    CLIENT_INTERACTIVE       = 0x0400
    CLIENT_SECURE_CONNECTION = 0x8000
    CLIENT_PLUGIN_AUTH       = 0x00080000

    # 8.0系で標準的なフラグのセット
    DEFAULT_CAPABILITIES = CLIENT_LONG_PASSWORD |
                           CLIENT_FOUND_ROWS |
                           CLIENT_LONG_FLAG |
                           CLIENT_CONNECT_WITH_DB |
                           CLIENT_PROTOCOL_41 |
                           CLIENT_INTERACTIVE |
                           CLIENT_SECURE_CONNECTION |
                           CLIENT_PLUGIN_AUTH
  end
end
