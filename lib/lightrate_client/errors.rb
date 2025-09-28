# frozen_string_literal: true

module LightrateClient
  class Error < StandardError; end

  class ConfigurationError < Error; end

  class AuthenticationError < Error; end

  class APIError < Error
    attr_reader :status_code, :response_body

    def initialize(message, status_code = nil, response_body = nil)
      super(message)
      @status_code = status_code
      @response_body = response_body
    end
  end

  class BadRequestError < APIError; end
  class UnauthorizedError < APIError; end
  class ForbiddenError < APIError; end
  class NotFoundError < APIError; end
  class UnprocessableEntityError < APIError; end
  class TooManyRequestsError < APIError; end
  class InternalServerError < APIError; end
  class ServiceUnavailableError < APIError; end

  class NetworkError < Error; end
  class TimeoutError < Error; end
end
