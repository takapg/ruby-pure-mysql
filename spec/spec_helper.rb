# frozen_string_literal: true

require 'bundler/setup'
require 'mysql2'
require 'ruby_pure_mysql'

RSpec.configure do |config|
  config.color = true
  config.formatter = :documentation

  # テスト開始前に 3307 ポートで自作サーバーを起動
  config.before(:suite) do
    Thread.new do
      RubyPureMysql.start(port: 3307)
    rescue Errno::EADDRINUSE
      # 既に起動している場合は無視
    end
    # サーバーが立ち上がるのを少し待つ
    sleep 0.5
  end
end
