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
        available_tokens: @available_tokens,
        max_tokens: @max_tokens
      }
    end

    # Reset bucket to empty state
    def reset
      @available_tokens = 0
    end
  end
end
