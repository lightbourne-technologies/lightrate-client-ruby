# frozen_string_literal: true

module LightrateClient
  # Request types
  class ConsumeTokensRequest
    attr_accessor :operation, :path, :http_method, :user_identifier, :tokens_requested, :timestamp

    def initialize(operation: nil, path: nil, http_method: nil, user_identifier:, tokens_requested:, timestamp: nil)
      @operation = operation
      @path = path
      @http_method = http_method
      @user_identifier = user_identifier
      @tokens_requested = tokens_requested
      @timestamp = timestamp || Time.now
    end

    def to_h
      {
        operation: @operation,
        path: @path,
        httpMethod: @http_method,
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
      return false if @path && @http_method.nil?

      true
    end
  end

  class CheckTokensRequest
    attr_accessor :operation, :path, :http_method, :user_identifier

    def initialize(operation: nil, path: nil, http_method: nil, user_identifier:)
      @operation = operation
      @path = path
      @http_method = http_method
      @user_identifier = user_identifier
    end

    def to_query_params
      params = { userIdentifier: @user_identifier }
      params[:operation] = @operation if @operation
      params[:path] = @path if @path
      params[:httpMethod] = @http_method if @http_method
      params
    end

    def valid?
      return false if @user_identifier.nil? || @user_identifier.empty?
      return false if @operation.nil? && @path.nil?
      return false if @operation && @path
      return false if @path && @http_method.nil?

      true
    end
  end

  # Response types
  class ConsumeTokensResponse
    attr_reader :success, :tokens_remaining, :error, :tokens_consumed

    def initialize(success:, tokens_remaining: nil, error: nil, tokens_consumed: 0)
      @success = success
      @tokens_remaining = tokens_remaining
      @error = error
      @tokens_consumed = tokens_consumed
    end

    def self.from_hash(hash)
      new(
        success: hash['success'] || hash[:success],
        tokens_remaining: hash['tokensRemaining'] || hash[:tokens_remaining],
        error: hash['error'] || hash[:error],
        tokens_consumed: hash['tokensConsumed'] || hash[:tokens_consumed] || 0
      )
    end
  end

  class ConsumeLocalBucketTokenResponse
    attr_reader :success, :used_local_token, :bucket_status

    def initialize(success:, used_local_token: false, bucket_status: nil)
      @success = success
      @used_local_token = used_local_token
      @bucket_status = bucket_status
    end

    # Indicates if this request required fetching tokens from the server
    def required_fetch?
      !@used_local_token
    end

    # Indicates if there were no more tokens available locally before this request
    def was_bucket_empty?
      !@used_local_token
    end
  end

  class CheckTokensResponse
    attr_reader :available, :tokens_remaining, :rule

    def initialize(available:, tokens_remaining: nil, rule: nil)
      @available = available
      @tokens_remaining = tokens_remaining
      @rule = rule
    end

    def self.from_hash(hash)
      rule = nil
      if hash['rule'] || hash[:rule]
        rule_hash = hash['rule'] || hash[:rule]
        rule = Rule.from_hash(rule_hash)
      end

      new(
        available: hash['available'] || hash[:available],
        tokens_remaining: hash['tokensRemaining'] || hash[:tokens_remaining],
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

  # Token bucket for local token management
  class TokenBucket
    attr_reader :available_tokens, :max_tokens

    def initialize(max_tokens)
      @max_tokens = max_tokens
      @available_tokens = 0
    end

    # Check if tokens are available locally
    def has_tokens?
      @available_tokens > 0
    end

    # Consume one token from the bucket
    # @return [Boolean] true if token was consumed, false if no tokens available
    def consume_token
      return false if @available_tokens <= 0
      
      @available_tokens -= 1
      true
    end

    # Consume multiple tokens from the bucket
    # @param count [Integer] Number of tokens to consume
    # @return [Integer] Number of tokens actually consumed
    def consume_tokens(count)
      return 0 if count <= 0 || @available_tokens <= 0
      
      tokens_to_consume = [count, @available_tokens].min
      @available_tokens -= tokens_to_consume
      tokens_to_consume
    end

    # Refill the bucket with tokens from the server
    # @param tokens_to_fetch [Integer] Number of tokens to fetch
    # @return [Integer] Number of tokens actually added to the bucket
    def refill(tokens_to_fetch)
      tokens_to_add = [tokens_to_fetch, @max_tokens - @available_tokens].min
      @available_tokens += tokens_to_add
      tokens_to_add
    end

    # Get current bucket status
    def status
      {
        tokens_remaining: @available_tokens,
        max_tokens: @max_tokens
      }
    end

    # Reset bucket to empty state
    def reset
      @available_tokens = 0
    end
  end
end
