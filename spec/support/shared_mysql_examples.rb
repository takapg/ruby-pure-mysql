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

  it 'executes SELECT 2; and returns 2' do
    results = client.query('SELECT 2;')
    expect(results.first.values.first).to eq(2)
  end

  it 'executes SELECT 100; and returns 100' do
    results = client.query('SELECT 100;')
    expect(results.first.values.first).to eq(100)
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
    begin
      client1&.close
    rescue StandardError
      nil
    end
    begin
      client2&.close
    rescue StandardError
      nil
    end
  end

  describe 'SELECT basic values' do
    it 'returns an integer for SELECT 123;' do
      results = client.query('SELECT 123;')
      expect(results.first.values.first).to eq(123)
    end

    it "returns a string for SELECT 'hello';" do
      results = client.query("SELECT 'hello';")
      expect(results.first.values.first).to eq('hello')
    end

    it 'returns a string for double quoted SELECT "world";' do
      results = client.query('SELECT "world";')
      expect(results.first.values.first).to eq('world')
    end

    it 'returns an empty string for SELECT "";' do
      results = client.query('SELECT "";')
      expect(results.first.values.first).to eq('')
    end
  end

  describe 'Query normalization and casing' do
    it 'is case-insensitive for SELECT keyword' do
      results = client.query("select 'case_test';")
      expect(results.first.values.first).to eq('case_test')
    end

    it 'handles trailing spaces and multiple semicolons' do
      # 最後のセミコロン除去ロジックのテスト
      results = client.query("SELECT 'space_test'  ;;;  ")
      expect(results.first.values.first).to eq('space_test')
    end
  end
end
