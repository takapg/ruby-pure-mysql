# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'MySQL Compatibility' do
  let(:client) do
    Mysql2::Client.new(
      host: ENV['DB_HOST'] || '127.0.0.1',
      username: ENV['DB_USER'] || 'root',
      port: 3306
    )
  end

  it 'executes SELECT 1;' do
    results = client.query('SELECT 1;')
    expect(results.first.values.first).to eq(1)
  end
end
