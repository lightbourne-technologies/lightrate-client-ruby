# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LightrateClient::Client do
  let(:client) { described_class.new('test_key', 'test_app') }

  describe '#initialize' do
    it 'creates a client with API key and application ID' do
      client = described_class.new('test_key', 'test_app')
      expect(client.configuration.api_key).to eq('test_key')
      expect(client.configuration.application_id).to eq('test_app')
    end

    it 'creates a client with API key, application ID and options' do
      client = described_class.new('test_key', 'test_app', timeout: 60)
      expect(client.configuration.api_key).to eq('test_key')
      expect(client.configuration.application_id).to eq('test_app')
      expect(client.configuration.timeout).to eq(60)
    end

    it 'raises error without API key' do
      expect { described_class.new }.to raise_error(LightrateClient::ConfigurationError, 'API key is required')
    end

    it 'raises error without application ID' do
      expect { described_class.new('test_key') }.to raise_error(LightrateClient::ConfigurationError, 'Application ID is required')
    end
  end

  describe 'request methods' do
    describe '#consume_tokens' do
      before do
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            headers: {
              'Authorization' => 'Bearer test_key',
              'Content-Type' => 'application/json',
              'Accept' => 'application/json',
              'User-Agent' => 'lightrate-client-ruby/1.0.2'
            },
            body: hash_including(
              applicationId: 'test_app',
              operation: 'send_email',
              userIdentifier: 'user123',
              tokensRequested: 1
            )
          )
          .to_return(
            status: 200, 
            body: { 
              tokensRemaining: 99, 
              tokensConsumed: 1,
              throttles: 0,
              rule: {
                id: "rule_123",
                name: "Test Rule",
                refillRate: 10,
                burstRate: 100,
                matcher: "send_email",
                httpMethod: nil,
                isDefault: false
              }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'consumes tokens by operation' do
        response = client.consume_tokens(
          operation: 'send_email',
          user_identifier: 'user123',
          tokens_requested: 1
        )

        expect(response.tokens_remaining).to eq(99)
        expect(response.tokens_consumed).to eq(1)
        expect(response.throttles).to eq(0)
        expect(response.rule).not_to be_nil
        expect(response.rule.id).to eq("rule_123")
        expect(response.rule.name).to eq("Test Rule")
      end

      it 'consumes tokens by path' do
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            headers: {
              'Authorization' => 'Bearer test_key',
              'Content-Type' => 'application/json',
              'Accept' => 'application/json',
              'User-Agent' => 'lightrate-client-ruby/1.0.2'
            },
            body: hash_including(
              applicationId: 'test_app',
              path: '/api/v1/emails/send',
              httpMethod: 'POST',
              userIdentifier: 'user123',
              tokensRequested: 1
            )
          )
          .to_return(
            status: 200, 
            body: { 
              tokensRemaining: 99, 
              tokensConsumed: 1,
              throttles: 0,
              rule: {
                id: "rule_456",
                name: "Email Rule",
                refillRate: 5,
                burstRate: 50,
                matcher: "/api/v1/emails/send",
                httpMethod: "POST",
                isDefault: false
              }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        response = client.consume_tokens(
          path: '/api/v1/emails/send',
          http_method: 'POST',
          user_identifier: 'user123',
          tokens_requested: 1
        )

        expect(response.tokens_remaining).to eq(99)
        expect(response.tokens_consumed).to eq(1)
        expect(response.throttles).to eq(0)
        expect(response.rule).not_to be_nil
        expect(response.rule.id).to eq("rule_456")
        expect(response.rule.name).to eq("Email Rule")
      end
    end

  end

  describe 'local token bucket functionality' do
    let(:client_with_buckets) do
      described_class.new(
        'test_key',
        'test_app',
        default_local_bucket_size: 50
      )
    end

    describe '#consume_local_bucket_token' do
      context 'when bucket is empty (first call)' do
        before do
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            headers: {
              'Authorization' => 'Bearer test_key',
              'Content-Type' => 'application/json',
              'Accept' => 'application/json',
              'User-Agent' => 'lightrate-client-ruby/1.0.2'
            },
            body: hash_including(
              applicationId: 'test_app',
              operation: 'send_email',
              userIdentifier: 'user123',
              tokensRequested: 50
            )
          )
            .to_return(
              status: 200,
              body: {
                tokensConsumed: 50,
                tokensRemaining: 950,
                throttles: 0,
                rule: {
                  id: "rule_send_email",
                  name: "Send Email Rule",
                  refillRate: 20,
                  burstRate: 200,
                  matcher: "send_email",
                  httpMethod: nil,
                  isDefault: false
                }
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        it 'fetches tokens from API and creates bucket with operation-specific size' do
          result = client_with_buckets.consume_local_bucket_token(
            operation: 'send_email',
            user_identifier: 'user123'
          )

          expect(result.success).to be true
          expect(result.used_local_token).to be false
          expect(result.bucket_status[:tokens_remaining]).to eq(49) # 50 fetched, 1 consumed
          expect(result.bucket_status[:max_tokens]).to eq(50)
        end

        it 'creates bucket with path-specific size' do
          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .with(
              body: hash_including(
                applicationId: 'test_app',
                path: '/api/v1/emails/send',
                httpMethod: 'POST',
                userIdentifier: 'user456',
                tokensRequested: 50
              )
            )
            .to_return(
              status: 200,
              body: {
                tokensConsumed: 50,
                tokensRemaining: 970,
                throttles: 0,
                rule: {
                  id: "rule_email_send",
                  name: "Email Send Rule",
                  refillRate: 15,
                  burstRate: 150,
                  matcher: "/api/v1/emails/send",
                  httpMethod: "POST",
                  isDefault: false
                }
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          result = client_with_buckets.consume_local_bucket_token(
            path: '/api/v1/emails/send',
            http_method: 'POST',
            user_identifier: 'user456'
          )

          expect(result.success).to be true
          expect(result.used_local_token).to be false
          expect(result.bucket_status[:tokens_remaining]).to eq(49) # 50 fetched, 1 consumed
          expect(result.bucket_status[:max_tokens]).to eq(50)
        end

        it 'uses default bucket size for unknown operation' do
          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .with(
              body: hash_including(
                applicationId: 'test_app',
                operation: 'unknown_operation',
                userIdentifier: 'user789',
                tokensRequested: 50
              )
            )
            .to_return(
              status: 200,
              body: {
                tokensConsumed: 50,
                tokensRemaining: 990,
                throttles: 0,
                rule: {
                  id: "rule_unknown",
                  name: "Unknown Operation Rule",
                  refillRate: 25,
                  burstRate: 250,
                  matcher: "unknown_operation",
                  httpMethod: nil,
                  isDefault: false
                }
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          result = client_with_buckets.consume_local_bucket_token(
            operation: 'unknown_operation',
            user_identifier: 'user789'
          )

          expect(result.success).to be true
          expect(result.used_local_token).to be false
          expect(result.bucket_status[:tokens_remaining]).to eq(49) # 50 fetched, 1 consumed
          expect(result.bucket_status[:max_tokens]).to eq(50)
        end
      end

      context 'when bucket has tokens (subsequent calls)' do
        before do
          # First call to populate bucket
          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .with(
              body: hash_including(
                applicationId: 'test_app',
                operation: 'send_sms',
                userIdentifier: 'user123',
                tokensRequested: 50
              )
            )
            .to_return(
              status: 200,
              body: {
                tokensConsumed: 50,
                tokensRemaining: 975,
                throttles: 0,
                rule: {
                  id: "rule_send_sms",
                  name: "Send SMS Rule",
                  refillRate: 30,
                  burstRate: 300,
                  matcher: "send_sms",
                  httpMethod: nil,
                  isDefault: false
                }
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        it 'uses local tokens without API call' do
          # First call populates bucket
          client_with_buckets.consume_local_bucket_token(
            operation: 'send_sms',
            user_identifier: 'user123'
          )

          # Second call should use local tokens
          result = client_with_buckets.consume_local_bucket_token(
            operation: 'send_sms',
            user_identifier: 'user123'
          )

          expect(result.success).to be true
          expect(result.used_local_token).to be true
          expect(result.bucket_status[:tokens_remaining]).to eq(48) # 50 - 1 (first call) - 1 (second call)
          expect(result.bucket_status[:max_tokens]).to eq(50)
        end
      end

      context 'when API call fails' do
        before do
          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .to_return(
              status: 200,
              body: {
                tokensRemaining: 0,
                tokensConsumed: 0,
                throttles: 0,
                rule: {
                  id: "rule_failed",
                  name: "Failed Rule",
                  refillRate: 0,
                  burstRate: 0,
                  matcher: "send_email",
                  httpMethod: nil,
                  isDefault: false
                }
              }.to_json
            )
        end

        it 'handles API failure gracefully' do
          response = client_with_buckets.consume_local_bucket_token(
            operation: 'send_email',
            user_identifier: 'user123'
          )
          
          expect(response.success).to be false
          expect(response.used_local_token).to be false
          expect(response.bucket_status[:tokens_remaining]).to eq(0)
        end
      end

      context 'with different users and operations' do
        before do
          # Stub multiple API calls for different users/operations
          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .with(
              body: hash_including(
                applicationId: 'test_app',
                operation: 'send_email',
                userIdentifier: 'user1',
                tokensRequested: 50
              )
            )
            .to_return(
              status: 200,
              body: { 
                tokensConsumed: 50, 
                tokensRemaining: 950,
                throttles: 0,
                rule: {
                  id: "rule_user1_email",
                  name: "User1 Email Rule",
                  refillRate: 20,
                  burstRate: 200,
                  matcher: "send_email",
                  httpMethod: nil,
                  isDefault: false
                }
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .with(
              body: hash_including(
                applicationId: 'test_app',
                operation: 'send_sms',
                userIdentifier: 'user1',
                tokensRequested: 50
              )
            )
            .to_return(
              status: 200,
              body: { 
                tokensConsumed: 50, 
                tokensRemaining: 950,
                throttles: 0,
                rule: {
                  id: "rule_user1_sms",
                  name: "User1 SMS Rule",
                  refillRate: 15,
                  burstRate: 150,
                  matcher: "send_sms",
                  httpMethod: nil,
                  isDefault: false
                }
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .with(
              body: hash_including(
                applicationId: 'test_app',
                operation: 'send_email',
                userIdentifier: 'user2',
                tokensRequested: 50
              )
            )
            .to_return(
              status: 200,
              body: { 
                tokensConsumed: 50, 
                tokensRemaining: 950,
                throttles: 0,
                rule: {
                  id: "rule_user2_email",
                  name: "User2 Email Rule",
                  refillRate: 20,
                  burstRate: 200,
                  matcher: "send_email",
                  httpMethod: nil,
                  isDefault: false
                }
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )
        end

        it 'maintains separate buckets for different users' do
          # User 1, email operation
          result1 = client_with_buckets.consume_local_bucket_token(
            operation: 'send_email',
            user_identifier: 'user1'
          )

          # User 1, SMS operation (different bucket)
          result2 = client_with_buckets.consume_local_bucket_token(
            operation: 'send_sms',
            user_identifier: 'user1'
          )

          # User 2, email operation (different user, same operation)
          result3 = client_with_buckets.consume_local_bucket_token(
            operation: 'send_email',
            user_identifier: 'user2'
          )

          expect(result1.bucket_status[:tokens_remaining]).to eq(49)
          expect(result1.bucket_status[:max_tokens]).to eq(50)

          expect(result2.bucket_status[:tokens_remaining]).to eq(49)
          expect(result2.bucket_status[:max_tokens]).to eq(50)

          expect(result3.bucket_status[:tokens_remaining]).to eq(49)
          expect(result3.bucket_status[:max_tokens]).to eq(50)
        end
      end
    end

  end
end
