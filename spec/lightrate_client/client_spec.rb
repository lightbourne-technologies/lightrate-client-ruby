# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LightrateClient::Client do
  let(:client) { described_class.new('test_key') }

  describe '#initialize' do
    it 'creates a client with just an API key' do
      client = described_class.new('test_key')
      expect(client.configuration.api_key).to eq('test_key')
      expect(client.configuration.base_url).to eq('https://api.lightrate.lightbournetechnologies.ca')
    end

    it 'creates a client with API key and options' do
      client = described_class.new('test_key', timeout: 60, base_url: 'https://custom.example.com')
      expect(client.configuration.api_key).to eq('test_key')
      expect(client.configuration.timeout).to eq(60)
      expect(client.configuration.base_url).to eq('https://custom.example.com')
    end

    it 'raises error without API key' do
      expect { described_class.new }.to raise_error(LightrateClient::ConfigurationError, 'API key is required')
    end
  end

  describe '#consume_tokens_with_request' do
    let(:request) do
      LightrateClient::ConsumeTokensRequest.new(
        operation: 'send_email',
        user_identifier: 'user123',
        tokens_requested: 1
      )
    end

    context 'with valid request' do
      before do
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            headers: {
              'Authorization' => 'Bearer test_key',
              'Content-Type' => 'application/json',
              'Accept' => 'application/json',
              'User-Agent' => 'lightrate-client-ruby/0.1.0'
            }
          )
          .to_return(
            status: 200,
            body: {
              success: true,
              remainingTokens: 99
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'consumes tokens successfully' do
        response = client.consume_tokens_with_request(request)

        expect(response.success).to be true
        expect(response.remaining_tokens).to eq(99)
      end
    end

    context 'with invalid request' do
      let(:invalid_request) { 'not a request object' }

      it 'raises ArgumentError' do
        expect { client.consume_tokens_with_request(invalid_request) }.to raise_error(ArgumentError, 'Invalid request')
      end
    end

    context 'with invalid request data' do
      let(:invalid_request) do
        LightrateClient::ConsumeTokensRequest.new(
          operation: 'send_email',
          user_identifier: '', # invalid: empty
          tokens_requested: 1
        )
      end

      it 'raises ArgumentError' do
        expect { client.consume_tokens_with_request(invalid_request) }.to raise_error(ArgumentError, 'Request validation failed')
      end
    end

    context 'when API returns error' do
      before do
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .to_return(
            status: 429,
            body: {
              error: 'Insufficient tokens available',
              remainingTokens: 0,
              tokensRequested: 1
            }.to_json
          )
      end

      it 'raises TooManyRequestsError' do
        expect { client.consume_tokens_with_request(request) }.to raise_error(LightrateClient::TooManyRequestsError)
      end
    end
  end

  describe '#check_tokens_with_request' do
    let(:request) do
      LightrateClient::CheckTokensRequest.new(
        operation: 'send_email',
        user_identifier: 'user123'
      )
    end

    context 'with valid request' do
      before do
        stub_request(:get, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/check')
          .with(
            headers: {
              'Authorization' => 'Bearer test_key',
              'Accept' => 'application/json',
              'User-Agent' => 'lightrate-client-ruby/0.1.0'
            },
            query: {
              operation: 'send_email',
              userIdentifier: 'user123'
            }
          )
          .to_return(
            status: 200,
            body: {
              available: true,
              remainingTokens: 100,
              rule: {
                name: 'Email Rule',
                refillRate: 10,
                burstRate: 50
              }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'checks tokens successfully' do
        response = client.check_tokens_with_request(request)

        expect(response.available).to be true
        expect(response.remaining_tokens).to eq(100)
        expect(response.rule.name).to eq('Email Rule')
        expect(response.rule.refill_rate).to eq(10)
        expect(response.rule.burst_rate).to eq(50)
      end
    end

    context 'with invalid request' do
      let(:invalid_request) { 'not a request object' }

      it 'raises ArgumentError' do
        expect { client.check_tokens_with_request(invalid_request) }.to raise_error(ArgumentError, 'Invalid request')
      end
    end
  end

  describe 'convenience methods' do
    describe '#consume_tokens' do
      before do
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            headers: {
              'Authorization' => 'Bearer test_key',
              'Content-Type' => 'application/json',
              'Accept' => 'application/json',
              'User-Agent' => 'lightrate-client-ruby/0.1.0'
            }
          )
          .to_return(
            status: 200, 
            body: { success: true, remainingTokens: 99 }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'consumes tokens by operation' do
        response = client.consume_tokens(
          operation: 'send_email',
          user_identifier: 'user123',
          tokens_requested: 1
        )

        expect(response.success).to be true
        expect(response.remaining_tokens).to eq(99)
      end

      it 'consumes tokens by path' do
        response = client.consume_tokens(
          path: '/api/v1/emails/send',
          user_identifier: 'user123',
          tokens_requested: 1
        )

        expect(response.success).to be true
        expect(response.remaining_tokens).to eq(99)
      end
    end

    describe '#check_tokens' do
      before do
        stub_request(:get, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/check')
          .with(
            headers: {
              'Authorization' => 'Bearer test_key',
              'Accept' => 'application/json',
              'User-Agent' => 'lightrate-client-ruby/0.1.0'
            }
          )
          .to_return(
            status: 200,
            body: {
              available: true,
              remainingTokens: 100,
              rule: { name: 'Test Rule', refillRate: 10, burstRate: 50 }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'checks tokens by operation' do
        response = client.check_tokens(
          operation: 'send_email',
          user_identifier: 'user123'
        )

        expect(response.available).to be true
        expect(response.remaining_tokens).to eq(100)
      end

      it 'checks tokens by path' do
        response = client.check_tokens(
          path: '/api/v1/emails/send',
          user_identifier: 'user123'
        )

        expect(response.available).to be true
        expect(response.remaining_tokens).to eq(100)
      end
    end
  end
end
