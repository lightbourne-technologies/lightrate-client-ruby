# frozen_string_literal: true

module LightrateClient
  class Configuration
    attr_accessor :api_key, :base_url, :timeout, :retry_attempts, :logger

    def initialize
      @base_url = "https://api.lightrate.lightbournetechnologies.ca"
      @timeout = 30
      @retry_attempts = 3
      @logger = nil
    end

    def valid?
      api_key && base_url
    end

    def to_h
      {
        api_key: "******",
        base_url: base_url,
        timeout: timeout,
        retry_attempts: retry_attempts,
        logger: logger
      }
    end
  end
end
