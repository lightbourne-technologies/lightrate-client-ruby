# frozen_string_literal: true

require_relative "lightrate_client/version"
require_relative "lightrate_client/client"
require_relative "lightrate_client/errors"
require_relative "lightrate_client/configuration"
require_relative "lightrate_client/types"

module LightrateClient
  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def client
      @client ||= Client.new
    end

    # Create a new client with just an API key
    def new_client(api_key, **options)
      Client.new(api_key, options)
    end

    def reset!
      @configuration = nil
      @client = nil
    end
  end
end
