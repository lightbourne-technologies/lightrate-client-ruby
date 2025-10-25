# frozen_string_literal: true

module LightrateClient
  # Request types
  class ConsumeTokensRequest
    attr_accessor :application_id, :operation, :path, :http_method, :user_identifier, :tokens_requested, :timestamp

    def initialize(application_id:, operation: nil, path: nil, http_method: nil, user_identifier:, tokens_requested:, timestamp: nil)
      @application_id = application_id
      @operation = operation
      @path = path
      @http_method = http_method
      @user_identifier = user_identifier
      @tokens_requested = tokens_requested
      @timestamp = timestamp || Time.now
    end

    def to_h
      {
        applicationId: @application_id,
        operation: @operation,
        path: @path,
        httpMethod: @http_method,
        userIdentifier: @user_identifier,
        tokensRequested: @tokens_requested,
        timestamp: @timestamp
      }.compact
    end

    def valid?
      return false if @application_id.nil? || @application_id.empty?
      return false if @user_identifier.nil? || @user_identifier.empty?
      return false if @tokens_requested.nil? || @tokens_requested <= 0
      return false if @operation.nil? && @path.nil?
      return false if @operation && @path
      return false if @path && @http_method.nil?

      true
    end
  end

  # Response types
  class ConsumeTokensResponse
    attr_reader :tokens_remaining, :tokens_consumed, :throttles, :rule

    def initialize(tokens_remaining:, tokens_consumed:, throttles: 0, rule: nil)
      @tokens_remaining = tokens_remaining
      @tokens_consumed = tokens_consumed
      @throttles = throttles
      @rule = rule
    end

    def self.from_hash(hash)
      rule = nil
      if hash['rule'] || hash[:rule]
        rule_hash = hash['rule'] || hash[:rule]
        rule = Rule.from_hash(rule_hash)
      end

      new(
        tokens_remaining: hash['tokensRemaining'] || hash[:tokens_remaining],
        tokens_consumed: hash['tokensConsumed'] || hash[:tokens_consumed],
        throttles: hash['throttles'] || hash[:throttles] || 0,
        rule: rule
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

  class Rule
    attr_reader :id, :name, :refill_rate, :burst_rate, :is_default, :matcher, :http_method

    def initialize(id:, name:, refill_rate:, burst_rate:, is_default: false, matcher: nil, http_method: nil)
      @id = id
      @name = name
      @refill_rate = refill_rate
      @burst_rate = burst_rate
      @is_default = is_default
      @matcher = matcher
      @http_method = http_method
    end

    def self.from_hash(hash)
      new(
        id: hash['id'] || hash[:id],
        name: hash['name'] || hash[:name],
        refill_rate: hash['refillRate'] || hash[:refill_rate],
        burst_rate: hash['burstRate'] || hash[:burst_rate],
        is_default: hash['isDefault'] || hash[:is_default] || false,
        matcher: hash['matcher'] || hash[:matcher],
        http_method: hash['httpMethod'] || hash[:http_method]
      )
    end
  end

  # Token bucket for local token management
  class TokenBucket
    attr_reader :available_tokens, :max_tokens, :rule_id, :matcher, :http_method, :last_accessed_at

    def initialize(max_tokens, rule_id:, matcher:, http_method: nil)
      @max_tokens = max_tokens
      @available_tokens = 0
      @rule_id = rule_id
      @matcher = matcher
      @http_method = http_method
      @last_accessed_at = Time.now
      @mutex = Mutex.new
    end

    # Check if tokens are available locally (caller must hold lock)
    # @return [Boolean] true if tokens are available
    def has_tokens?
      @available_tokens > 0
    end

    # Consume one token from the bucket (caller must hold lock)
    # @return [Boolean] true if token was consumed, false if no tokens available
    def consume_token
      return false if @available_tokens <= 0
      
      @available_tokens -= 1
      true
    end

    # Consume multiple tokens from the bucket (caller must hold lock)
    # @param count [Integer] Number of tokens to consume
    # @return [Integer] Number of tokens actually consumed
    def consume_tokens(count)
      return 0 if count <= 0 || @available_tokens <= 0
      
      tokens_to_consume = [count, @available_tokens].min
      @available_tokens -= tokens_to_consume
      tokens_to_consume
    end

    # Refill the bucket with tokens from the server (caller must hold lock)
    # @param tokens_to_add [Integer] Number of tokens to add
    # @return [Integer] Number of tokens actually added to the bucket
    def refill(tokens_to_add)
      touch
      tokens_to_add = [tokens_to_add, @max_tokens - @available_tokens].min
      @available_tokens += tokens_to_add
      tokens_to_add
    end

    # Get current bucket status (caller must hold lock)
    # @return [Hash] Current bucket status with tokens_remaining and max_tokens
    def status
      {
        tokens_remaining: @available_tokens,
        max_tokens: @max_tokens
      }
    end

    # Reset bucket to empty state (caller must hold lock)
    def reset
      @available_tokens = 0
    end

    # Check if this bucket matches the given request
    def matches?(operation, path, http_method)
      return false if expired?
      return false unless @matcher
      
      begin
        matcher_regex = Regexp.new(@matcher)
        
        # For operation-based requests, match against operation
        if operation
          return matcher_regex.match?(operation) && @http_method.nil?
        end
        
        # For path-based requests, match against path and HTTP method
        if path
          return matcher_regex.match?(path) && @http_method == http_method
        end
        
        false
      rescue RegexpError
        # If matcher is not a valid regex, fall back to exact match
        if operation
          return @matcher == operation && @http_method.nil?
        elsif path
          return @matcher == path && @http_method == http_method
        end
        false
      end
    end

    # Check if bucket has expired (not accessed in 60 seconds)
    def expired?
      Time.now - @last_accessed_at > 60
    end

    # Update last accessed time
    def touch
      @last_accessed_at = Time.now
    end

    # Check tokens and consume atomically (caller must hold lock)
    # This prevents race conditions between checking and consuming
    # @return [Array] [has_tokens, consumed_successfully]
    def check_and_consume_token
      synchronize do
        touch
        has_tokens = @available_tokens > 0
        if has_tokens
          @available_tokens -= 1
          true
        else
          false
        end
      end
    end

    # Synchronize access to this bucket for thread-safe operations
    # @yield Block to execute under bucket lock
    def synchronize(&block)
      @mutex.synchronize(&block)
    end
  end
end
