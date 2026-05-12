# frozen_string_literal: true

RSpec.shared_examples 'a MySQL-compatible server' do |port|
  let(:client) do
    Mysql2::Client.new(
      host: '127.0.0.1',
      username: 'root',
      port: port,
      connect_timeout: 2
    )
  end

  after do
    client&.close
  rescue StandardError
    # 接続が既に切れている場合のクローズエラーを無視
  end

  it 'executes SELECT 1; and returns 1' do
    results = client.query('SELECT 1;')
    expect(results.first.values.first).to eq(1)
  end

  it 'executes SELECT 1; multiple times in the same session' do
    3.times do
      results = client.query('SELECT 1;')
      expect(results.first.values.first).to eq(1)
    end
  end

  it 'allows new connections after a previous client disconnects' do
    client1 = Mysql2::Client.new(host: '127.0.0.1', port: port, username: 'root')
    client2 = nil

    expect(client1.query('SELECT 1;').first.values.first).to eq(1)
    client1.close

    client2 = Mysql2::Client.new(host: '127.0.0.1', port: port, username: 'root')
    expect(client2.query('SELECT 1;').first.values.first).to eq(1)
  ensure
    client1&.close rescue nil
    client2&.close rescue nil
  end
end
