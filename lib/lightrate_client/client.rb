# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "json"
require "time"

module LightrateClient
  class Client
    attr_reader :configuration, :token_buckets

    def initialize(api_key = nil, options = {})
      if api_key
        # Create a new configuration with the provided API key
        @configuration = LightrateClient::Configuration.new.tap do |c|
          c.api_key = api_key
          c.base_url = options[:base_url] || LightrateClient.configuration.base_url
          c.timeout = options[:timeout] || LightrateClient.configuration.timeout
          c.retry_attempts = options[:retry_attempts] || LightrateClient.configuration.retry_attempts
          c.logger = options[:logger] || LightrateClient.configuration.logger
          c.local_token_bucket_size = options[:local_token_bucket_size] || LightrateClient.configuration.local_token_bucket_size
        end
      else
        @configuration = options.is_a?(LightrateClient::Configuration) ? options : LightrateClient.configuration
      end
      
      validate_configuration!
      setup_connection
      setup_token_buckets
    end

    # Consume tokens from the token bucket using a request object
    # @param request [ConsumeTokensRequest] The token consumption request
    # @return [ConsumeTokensResponse] The response indicating success/failure and remaining tokens
    def consume_tokens_with_request(request)
      raise ArgumentError, "Invalid request" unless request.is_a?(ConsumeTokensRequest)
      raise ArgumentError, "Request validation failed" unless request.valid?

      post("/api/v1/tokens/consume", request.to_h)
    end

    # Check available tokens without consuming them using a request object
    # @param request [CheckTokensRequest] The token check request
    # @return [CheckTokensResponse] The response with available tokens and rule info
    def check_tokens_with_request(request)
      raise ArgumentError, "Invalid request" unless request.is_a?(CheckTokensRequest)
      raise ArgumentError, "Request validation failed" unless request.valid?

      get("/api/v1/tokens/check", request.to_query_params)
    end

    # Consume tokens by operation or path using local bucket
    # @param operation [String, nil] The operation name (mutually exclusive with path)
    # @param path [String, nil] The API path (mutually exclusive with operation)
    # @param user_identifier [String] The user identifier
    # @param tokens_requested [Integer] Number of tokens to consume
    def consume_local_bucket_token(operation: nil, path: nil, user_identifier:)
      # Get or create bucket for this user/operation/path combination
      bucket = get_or_create_bucket(user_identifier, operation, path)

      tokens_available_locally = bucket.has_tokens?
      
      # Check if we have enough tokens available locally, if not, get more from API
      unless tokens_available_locally
        # Use local tokens
        tokens_to_fetch = @configuration.local_token_bucket_size
        request = ConsumeTokensRequest.new(
          operation: operation,
          path: path,
          user_identifier: user_identifier,
          tokens_requested: tokens_to_fetch
        )
        # Make the API call
        response = post("/api/v1/tokens/consume", request.to_h)

        if response['tokensConsumed'] > 0
          # Refill the bucket with the fetched tokens
          bucket.refill(response['tokensConsumed'])
        end
      end

      # Now try to consume the requested tokens from the bucket
      consumed_successfully = bucket.consume_token

      {
        success: consumed_successfully,
        used_local_token: tokens_available_locally,
        bucket_status: bucket.status
      }
    end

    def consume_tokens(operation: nil, path: nil, user_identifier:, tokens_requested:)
      request = ConsumeTokensRequest.new(
        operation: operation,
        path: path,
        user_identifier: user_identifier,
        tokens_requested: tokens_requested
      )
      consume_tokens_with_request(request)
    end

    # Check tokens by operation or path
    # @param operation [String, nil] The operation name (mutually exclusive with path)
    # @param path [String, nil] The API path (mutually exclusive with operation)
    # @param user_identifier [String] The user identifier
    def check_tokens(operation: nil, path: nil, user_identifier:)
      request = CheckTokensRequest.new(
        operation: operation,
        path: path,
        user_identifier: user_identifier
      )
      check_tokens_with_request(request)
    end

    private

    def setup_token_buckets
      @token_buckets = {}
    end

    def get_or_create_bucket(user_identifier, operation, path)
      # Create a unique key for this user/operation/path combination
      bucket_key = create_bucket_key(user_identifier, operation, path)
      
      # Return existing bucket or create a new one
      @token_buckets[bucket_key] ||= TokenBucket.new(@configuration.local_token_bucket_size)
    end

    def create_bucket_key(user_identifier, operation, path)
      # Create a unique key that combines user, operation, and path
      if operation
        "#{user_identifier}:operation:#{operation}"
      elsif path
        "#{user_identifier}:path:#{path}"
      else
        raise ArgumentError, "Either operation or path must be specified"
      end
    end

    def validate_configuration!
      raise ConfigurationError, "API key is required" unless configuration.api_key
      raise ConfigurationError, "Base URL is required" unless configuration.base_url
    end

    def setup_connection
      @connection = Faraday.new(url: configuration.base_url) do |conn|
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
