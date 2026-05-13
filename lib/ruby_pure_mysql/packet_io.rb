# frozen_string_literal: true

require 'socket'
require 'timeout'

module RubyPureMysql
  # MySQL プロトコルのパケット単位での読み書き（フレーミング）を制御します。
  # 3バイトの長さヘッダと1バイトのシーケンス番号の処理を担当します。
  class PacketIO
    # MySQL の最大パケット長 (16MB - 1)
    MAX_PACKET_LEN = 0xFF_FF_FF

    # @param client [TCPSocket] クライアントソケット
    # @param timeout [Integer] 読み取りタイムアウト（秒）
    def initialize(client, timeout)
      @client = client
      @timeout = timeout
    end

    # ソケットから次のパケットを読み取ります。
    # @return [Array<(String, Integer)>, nil] ペイロードとシーケンス番号のペア。切断時は nil。
    # @raise [ProtocolError] パケット長が不正な場合
    # @raise [InsufficientDataError] データが途中で途切れた場合
    # @raise [Timeout::Error] タイムアウトした場合
    def read_packet
      header = read_exact(4)
      return nil unless header

      # 3バイトの長さ(Little Endian)と1バイトのシーケンス番号を取得
      len = header.unpack1('V') & 0xFFFFFF
      seq = header.getbyte(3)

      # 0バイトパケットはエラーとする（実装上の制約）
      raise ProtocolError, "Invalid packet length: #{len}" if len <= 0
      # マルチパケット（16MB超）は現状未サポート
      raise ProtocolError, 'Multi-packet payloads are not supported' if len == MAX_PACKET_LEN

      [read_exact(len), seq]
    end

    # ソケットへパケットを書き込みます。
    # @param payload [String] 送信するデータ本体
    # @param seq [Integer] シーケンス番号
    def write_packet(payload, seq)
      # 長さ(3byte) + シーケンス(1byte) のヘッダを構成
      header = [payload.bytesize].pack('V')[0, 3] + [seq % 256].pack('C')
      @client.write(header + payload)
    end

    private

    # 指定されたバイト数に達するまでノンブロッキングで読み取ります。
    # @param length [Integer] 読み取るべきバイト数
    # @return [String] 読み取ったデータ
    def read_exact(length)
      buffer = +''
      while buffer.bytesize < length
        chunk = @client.read_nonblock(length - buffer.bytesize, exception: false)
        case chunk
        when :wait_readable
          wait_socket
        when nil
          raise InsufficientDataError, 'Connection closed by peer'
        else
          buffer << chunk
        end
      end
      buffer
    end

    # ソケットが読み取り可能になるまで待機します。
    def wait_socket
      result = IO.select([@client], nil, nil, @timeout)
      raise Timeout::Error, 'Read timeout' if result.nil?
    end
  end
end
