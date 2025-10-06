# frozen_string_literal: true

module LightrateClient
  class Configuration
    attr_accessor :api_key, :application_id, :timeout, :retry_attempts, :logger, :default_local_bucket_size

    def initialize
      @timeout = 30
      @retry_attempts = 3
      @logger = nil
      @default_local_bucket_size = 5
    end

    def valid?
      api_key && application_id
    end

    def to_h
      {
        api_key: "******",
        application_id: application_id,
        timeout: timeout,
        retry_attempts: retry_attempts,
        logger: logger,
        default_local_bucket_size: default_local_bucket_size
      }
    end
  end
end
