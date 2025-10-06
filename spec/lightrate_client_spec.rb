# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LightrateClient do
  describe '.configure' do
    it 'yields configuration object' do
      expect { |b| described_class.configure(&b) }.to yield_with_args(described_class.configuration)
    end
  end

  describe '.configuration' do
    it 'returns a Configuration instance' do
      expect(described_class.configuration).to be_a(LightrateClient::Configuration)
    end

    it 'returns the same instance' do
      expect(described_class.configuration).to be(described_class.configuration)
    end
  end

  describe '.client' do
    before do
      described_class.configure do |config|
        config.api_key = 'test_key'
        config.application_id = 'test_app'
      end
    end

    it 'returns a Client instance' do
      expect(described_class.client).to be_a(LightrateClient::Client)
    end

    it 'returns the same instance' do
      expect(described_class.client).to be(described_class.client)
    end
  end

  describe '.new_client' do
    it 'creates a new client with API key and application ID' do
      client = described_class.new_client('test_key', 'test_app')
      expect(client).to be_a(LightrateClient::Client)
      expect(client.configuration.api_key).to eq('test_key')
      expect(client.configuration.application_id).to eq('test_app')
    end

    it 'creates a new client with API key, application ID and options' do
      client = described_class.new_client('test_key', 'test_app', timeout: 60)
      expect(client).to be_a(LightrateClient::Client)
      expect(client.configuration.api_key).to eq('test_key')
      expect(client.configuration.application_id).to eq('test_app')
      expect(client.configuration.timeout).to eq(60)
    end
  end

  describe '.reset!' do
    it 'resets configuration and client' do
      described_class.configure { |config| config.api_key = 'test'; config.application_id = 'test_app' }
      described_class.client

      described_class.reset!

      expect(described_class.configuration.api_key).to be_nil
      expect(described_class.configuration.application_id).to be_nil
      expect(described_class.instance_variable_get(:@client)).to be_nil
    end
  end
end
