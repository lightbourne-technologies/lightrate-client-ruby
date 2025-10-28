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
      # Synchronize the entire process to prevent race conditions
      # First, try to find an existing bucket that matches this request
      bucket = find_bucket_by_matcher(user_identifier, operation, path, http_method)

      if bucket && bucket.check_and_consume_token
        return LightrateClient::ConsumeLocalBucketTokenResponse.new(
          success: true,
          used_local_token: true,
          bucket_status: bucket.status
        )
      end

      # No matching bucket or bucket is empty - make API call to get tokens and rule info
      tokens_to_fetch = @configuration.default_local_bucket_size
      
      # Make the API call
      response = consume_tokens(operation: operation, path: path, http_method: http_method, user_identifier: user_identifier, tokens_requested: tokens_to_fetch)

      if response.rule.is_default
        return LightrateClient::ConsumeLocalBucketTokenResponse.new(
          success: response.tokens_consumed > 0,
          used_local_token: false,
          bucket_status: nil
        )
      end

      bucket = check_and_create_bucket(user_identifier, response.rule, response.tokens_consumed)

      tokens_available = bucket.check_and_consume_token

      return LightrateClient::ConsumeLocalBucketTokenResponse.new(
        success: tokens_available,
        used_local_token: false,
        bucket_status: bucket.status
      )
    end

    def consume_token_from_bucket(bucket, provided_tokens = 0)
      bucket.synchronize do
        fetch_required = !bucket.has_tokens? || bucket.expired?

        token_available = bucket.check_and_consume_token

        [token_available, fetch_required]
      end
    end

    def consume_tokens(operation: nil, path: nil, http_method: nil, user_identifier:, tokens_requested:)
      request = LightrateClient::ConsumeTokensRequest.new(
        application_id: @configuration.application_id,
        operation: operation,
        path: path,
        http_method: http_method,
        user_identifier: user_identifier,
        tokens_requested: tokens_requested,
        tokens_requested_for_default_bucket_match: 1
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
      # Parse JSON response if it's a string
      response = JSON.parse(response) if response.is_a?(String)
      LightrateClient::ConsumeTokensResponse.from_hash(response)
    end

    def setup_token_buckets
      @token_buckets = {}
      @buckets_mutex = Mutex.new
    end

    def check_and_create_bucket(user_identifier, rule, initial_tokens)
      bucket_key = "#{user_identifier}:rule:#{rule.id}"
      
      @buckets_mutex.synchronize do
        return @token_buckets[bucket_key] if @token_buckets[bucket_key] && @token_buckets[bucket_key].has_tokens?

        @token_buckets[bucket_key] ||= begin
          bucket_size = @configuration.default_local_bucket_size
          TokenBucket.new(bucket_size, rule_id: rule.id, matcher: rule.matcher, http_method: rule.http_method, user_identifier: user_identifier)
        end
      end

      @token_buckets[bucket_key].refill(initial_tokens)

      @token_buckets[bucket_key]
    end

    def find_bucket_by_matcher(user_identifier, operation, path, http_method)
      @token_buckets.values.find do |bucket|
        bucket.matches?(operation, path, http_method) && bucket.user_identifier == user_identifier
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
