# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "json"
require "time"

module LightrateClient
  class Client
    attr_reader :configuration, :token_buckets

    def initialize(api_key = nil, application_id = nil, options = {})
      if api_key
        # Create a new configuration with the provided API key and application ID
        @configuration = LightrateClient::Configuration.new.tap do |c|
          c.api_key = api_key
          c.application_id = application_id
          c.timeout = options[:timeout] || LightrateClient.configuration.timeout
          c.retry_attempts = options[:retry_attempts] || LightrateClient.configuration.retry_attempts
          c.logger = options[:logger] || LightrateClient.configuration.logger
          c.default_local_bucket_size = options[:default_local_bucket_size] || LightrateClient.configuration.default_local_bucket_size
        end
      else
        @configuration = options.is_a?(LightrateClient::Configuration) ? options : LightrateClient.configuration
      end
      
      
      validate_configuration!
      setup_connection
      setup_token_buckets
    end

    # Consume tokens by operation or path using local bucket
    # @param operation [String, nil] The operation name (mutually exclusive with path)
    # @param path [String, nil] The API path (mutually exclusive with operation)
    # @param http_method [String, nil] The HTTP method (required when path is provided)
    # @param user_identifier [String] The user identifier
    # @param tokens_requested [Integer] Number of tokens to consume
    def consume_local_bucket_token(operation: nil, path: nil, http_method: nil, user_identifier:)
      # Get or create bucket for this user/operation/path combination
      bucket = get_or_create_bucket(user_identifier, operation, path, http_method)

      # Use the bucket's mutex to synchronize the entire operation
      # This prevents race conditions between multiple threads trying to consume from the same bucket
      bucket.synchronize do
        # Try to consume a token atomically first
        has_tokens, consumed_successfully = bucket.check_and_consume_token
        
        # If we successfully consumed a local token, return success
        if consumed_successfully
          return LightrateClient::ConsumeLocalBucketTokenResponse.new(
            success: true,
            used_local_token: true,
            bucket_status: bucket.status
          )
        end

        # No local tokens available, need to fetch from API
        tokens_to_fetch = get_bucket_size_for_operation(operation, path)
        
        # Make API call
        request = LightrateClient::ConsumeTokensRequest.new(
          application_id: @configuration.application_id,
          operation: operation,
          path: path,
          http_method: http_method,
          user_identifier: user_identifier,
          tokens_requested: tokens_to_fetch
        )
        
        # Make the API call
        response = post("/api/v1/tokens/consume", request.to_h)
        tokens_consumed = response['tokensConsumed']&.to_i || 0

        # If we got tokens from API, refill the bucket and try to consume
        if tokens_consumed > 0
          tokens_added, has_tokens_after_refill = bucket.refill_and_check(tokens_consumed)
          
          # Try to consume a token after refilling
          _, final_consumed = bucket.check_and_consume_token
          
          return LightrateClient::ConsumeLocalBucketTokenResponse.new(
            success: final_consumed,
            used_local_token: false,
            bucket_status: bucket.status
          )
        else
          # No tokens available from API
          return LightrateClient::ConsumeLocalBucketTokenResponse.new(
            success: false,
            used_local_token: false,
            bucket_status: bucket.status
          )
        end
      end
    end

    def consume_tokens(operation: nil, path: nil, http_method: nil, user_identifier:, tokens_requested:)
      request = LightrateClient::ConsumeTokensRequest.new(
        application_id: @configuration.application_id,
        operation: operation,
        path: path,
        http_method: http_method,
        user_identifier: user_identifier,
        tokens_requested: tokens_requested
      )
      consume_tokens_with_request(request)
    end

    private

    # Consume tokens from the token bucket using a request object
    # @param request [ConsumeTokensRequest] The token consumption request
    # @return [ConsumeTokensResponse] The response indicating success/failure and remaining tokens
    def consume_tokens_with_request(request)
      raise ArgumentError, "Invalid request" unless request.is_a?(LightrateClient::ConsumeTokensRequest)
      raise ArgumentError, "Request validation failed" unless request.valid?

      response = post("/api/v1/tokens/consume", request.to_h)
      LightrateClient::ConsumeTokensResponse.from_hash(response)
    end

    def setup_token_buckets
      @token_buckets = {}
      @buckets_mutex = Mutex.new
    end

    def get_or_create_bucket(user_identifier, operation, path, http_method = nil)
      # Create a unique key for this user/operation/path combination
      bucket_key = create_bucket_key(user_identifier, operation, path, http_method)
      
      # Double-checked locking pattern for thread-safe bucket creation
      return @token_buckets[bucket_key] if @token_buckets[bucket_key]
      
      @buckets_mutex.synchronize do
        # Check again inside the mutex to prevent duplicate creation
        @token_buckets[bucket_key] ||= begin
          bucket_size = get_bucket_size_for_operation(operation, path)
          TokenBucket.new(bucket_size)
        end
      end
      
      @token_buckets[bucket_key]
    end

    def get_bucket_size_for_operation(operation, path)
      # Always use the default bucket size for all operations and paths
      @configuration.default_local_bucket_size
    end

    def create_bucket_key(user_identifier, operation, path, http_method = nil)
      # Create a unique key that combines user, operation, and path
      if operation
        "#{user_identifier}:operation:#{operation}"
      elsif path
        "#{user_identifier}:path:#{path}:#{http_method}"
      else
        raise ArgumentError, "Either operation or path must be specified"
      end
    end

    def validate_configuration!
      raise ConfigurationError, "API key is required" unless configuration.api_key
      raise ConfigurationError, "Application ID is required" unless configuration.application_id
    end

    def setup_connection
      @connection = Faraday.new(url: "https://api.lightrate.lightbournetechnologies.ca") do |conn|
        conn.request :json
        conn.response :json, content_type: /\bjson$/
        conn.response :logger, configuration.logger if configuration.logger
        conn.use Faraday::Retry::Middleware, retry_options
        conn.adapter Faraday.default_adapter
      end
    end

    def retry_options
      {
        max: configuration.retry_attempts,
        interval: 0.5,
        backoff_factor: 2,
        retry_if: ->(env, _exception) { should_retry?(env) }
      }
    end

    def should_retry?(env)
      status = env.status
      [429, 500, 502, 503, 504].include?(status)
    end

    def get(path, params = {})
      request(:get, path, params: params)
    end

    def post(path, body = {})
      request(:post, path, body: body)
    end

    def request(method, path, **options)
      response = @connection.public_send(method, path) do |req|
        req.headers["Authorization"] = "Bearer #{configuration.api_key}"
        req.headers["User-Agent"] = "lightrate-client-ruby/#{VERSION}"
        req.headers["Accept"] = "application/json"
        req.headers["Content-Type"] = "application/json"

        req.params.merge!(options[:params]) if options[:params]
        req.body = options[:body].to_json if options[:body]

        req.options.timeout = configuration.timeout
      end

      handle_response(response)
    rescue Faraday::TimeoutError
      raise TimeoutError, "Request timed out after #{configuration.timeout} seconds"
    rescue Faraday::ConnectionFailed, Faraday::SSLError => e
      raise NetworkError, "Network error: #{e.message}"
    end

    def handle_response(response)
      case response.status
      when 200..299
        response.body
      when 400
        raise BadRequestError.new("Bad Request", response.status, response.body)
      when 401
        raise UnauthorizedError.new("Unauthorized", response.status, response.body)
      when 403
        raise ForbiddenError.new("Forbidden", response.status, response.body)
      when 404
        raise NotFoundError.new("Not Found", response.status, response.body)
      when 422
        raise UnprocessableEntityError.new("Unprocessable Entity", response.status, response.body)
      when 429
        raise TooManyRequestsError.new("Too Many Requests", response.status, response.body)
      when 500
        raise InternalServerError.new("Internal Server Error", response.status, response.body)
      when 503
        raise ServiceUnavailableError.new("Service Unavailable", response.status, response.body)
      else
        raise APIError.new("API Error: #{response.status}", response.status, response.body)
      end
    end
  end
end
