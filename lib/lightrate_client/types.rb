# frozen_string_literal: true

module LightrateClient
  # Request types
  class ConsumeTokensRequest
    attr_accessor :operation, :path, :user_identifier, :tokens_requested, :timestamp

    def initialize(operation: nil, path: nil, user_identifier:, tokens_requested:, timestamp: nil)
      @operation = operation
      @path = path
      @user_identifier = user_identifier
      @tokens_requested = tokens_requested
      @timestamp = timestamp || Time.now
    end

    def to_h
      {
        operation: @operation,
        path: @path,
        userIdentifier: @user_identifier,
        tokensRequested: @tokens_requested,
        timestamp: @timestamp
      }.compact
    end

    def valid?
      return false if @user_identifier.nil? || @user_identifier.empty?
      return false if @tokens_requested.nil? || @tokens_requested <= 0
      return false if @operation.nil? && @path.nil?
      return false if @operation && @path

      true
    end
  end

  class CheckTokensRequest
    attr_accessor :operation, :path, :user_identifier

    def initialize(operation: nil, path: nil, user_identifier:)
      @operation = operation
      @path = path
      @user_identifier = user_identifier
    end

    def to_query_params
      params = { userIdentifier: @user_identifier }
      params[:operation] = @operation if @operation
      params[:path] = @path if @path
      params
    end

    def valid?
      return false if @user_identifier.nil? || @user_identifier.empty?
      return false if @operation.nil? && @path.nil?
      return false if @operation && @path

      true
    end
  end

  # Response types
  class ConsumeTokensResponse
    attr_reader :success, :remaining_tokens, :error

    def initialize(success:, remaining_tokens: nil, error: nil)
      @success = success
      @remaining_tokens = remaining_tokens
      @error = error
    end

    def self.from_hash(hash)
      new(
        success: hash['success'] || hash[:success],
        remaining_tokens: hash['remainingTokens'] || hash[:remaining_tokens],
        error: hash['error'] || hash[:error]
      )
    end
  end

  class CheckTokensResponse
    attr_reader :available, :remaining_tokens, :rule

    def initialize(available:, remaining_tokens:, rule:)
      @available = available
      @remaining_tokens = remaining_tokens
      @rule = rule
    end

    def self.from_hash(hash)
      rule_data = hash['rule'] || hash[:rule]
      rule = rule_data ? Rule.from_hash(rule_data) : nil
      
      new(
        available: hash['available'] || hash[:available],
        remaining_tokens: hash['remainingTokens'] || hash[:remaining_tokens],
        rule: rule
      )
    end
  end

  class Rule
    attr_reader :name, :refill_rate, :burst_rate

    def initialize(name:, refill_rate:, burst_rate:)
      @name = name
      @refill_rate = refill_rate
      @burst_rate = burst_rate
    end

    def self.from_hash(hash)
      new(
        name: hash['name'] || hash[:name],
        refill_rate: hash['refillRate'] || hash[:refill_rate],
        burst_rate: hash['burstRate'] || hash[:burst_rate]
      )
    end
  end
end
