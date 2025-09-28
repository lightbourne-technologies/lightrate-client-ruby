# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "json"
require "time"

module LightrateClient
  class Client
    attr_reader :configuration

    def initialize(api_key = nil, options = {})
      if api_key
        # Create a new configuration with the provided API key
        @configuration = LightrateClient::Configuration.new.tap do |c|
          c.api_key = api_key
          c.base_url = options[:base_url] || LightrateClient.configuration.base_url
          c.timeout = options[:timeout] || LightrateClient.configuration.timeout
          c.retry_attempts = options[:retry_attempts] || LightrateClient.configuration.retry_attempts
          c.logger = options[:logger] || LightrateClient.configuration.logger
        end
      else
        @configuration = options.is_a?(LightrateClient::Configuration) ? options : LightrateClient.configuration
      end
      
      validate_configuration!
      setup_connection
    end

    # Consume tokens from the token bucket using a request object
    # @param request [ConsumeTokensRequest] The token consumption request
    # @return [ConsumeTokensResponse] The response indicating success/failure and remaining tokens
    def consume_tokens_with_request(request)
      raise ArgumentError, "Invalid request" unless request.is_a?(ConsumeTokensRequest)
      raise ArgumentError, "Request validation failed" unless request.valid?

      response = post("/api/v1/tokens/consume", request.to_h)
      ConsumeTokensResponse.from_hash(response)
    end

    # Check available tokens without consuming them using a request object
    # @param request [CheckTokensRequest] The token check request
    # @return [CheckTokensResponse] The response with available tokens and rule info
    def check_tokens_with_request(request)
      raise ArgumentError, "Invalid request" unless request.is_a?(CheckTokensRequest)
      raise ArgumentError, "Request validation failed" unless request.valid?

      response = get("/api/v1/tokens/check", request.to_query_params)
      CheckTokensResponse.from_hash(response)
    end

    # Consume tokens by operation or path
    # @param operation [String, nil] The operation name (mutually exclusive with path)
    # @param path [String, nil] The API path (mutually exclusive with operation)
    # @param user_identifier [String] The user identifier
    # @param tokens_requested [Integer] Number of tokens to consume
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
