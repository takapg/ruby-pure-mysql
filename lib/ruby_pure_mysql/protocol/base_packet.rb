# frozen_string_literal: true

module RubyPureMysql
  module Protocol
    # すべての MySQL パケットクラスの基底となる抽象クラスです。
    # 共通のデータ生成ヘルパーを提供し、パケット構造のインターフェースを定義します。
    class BasePacket
      include PacketHelper

      # パケットのボディ（ペイロード）をバイナリ文字列として生成します。
      # このメソッドはサブクラスで必ずオーバーライドされる必要があります。
      #
      # @return [String] バイナリ形式のペイロード文字列
      # @raise [NotImplementedError] サブクラスで実装されていない場合に発生
      def payload
        raise NotImplementedError, "#{self.class} は payload メソッドを実装する必要があります"
      end

      # デバッグ用：ペイロードの中身を 16 進数の文字列（スペース区切り）で返します。
      # パケットが正しくパッキングされているか確認する際に役立ちます。
      #
      # @return [String] 16進数ダンプ
      def inspect_payload
        payload.unpack1('H*').scan(/../).join(' ')
      end
    end
  end
end
