# frozen_string_literal: true

module RubyPureMysql
  class ProtocolError < StandardError; end
  class AuthenticationError < StandardError; end
  class InsufficientDataError < ProtocolError; end
end
