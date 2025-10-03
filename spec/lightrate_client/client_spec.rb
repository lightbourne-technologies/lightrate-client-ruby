# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LightrateClient::Client do
  let(:client) { described_class.new('test_key') }

  describe '#initialize' do
    it 'creates a client with just an API key' do
      client = described_class.new('test_key')
      expect(client.configuration.api_key).to eq('test_key')
    end

    it 'creates a client with API key and options' do
      client = described_class.new('test_key', timeout: 60)
      expect(client.configuration.api_key).to eq('test_key')
      expect(client.configuration.timeout).to eq(60)
    end

    it 'raises error without API key' do
      expect { described_class.new }.to raise_error(LightrateClient::ConfigurationError, 'API key is required')
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
              'User-Agent' => 'lightrate-client-ruby/1.0.0'
            },
            body: hash_including(
              operation: 'send_email',
              userIdentifier: 'user123',
              tokensRequested: 1
            )
          )
          .to_return(
            status: 200, 
            body: { success: true, tokensRemaining: 99, tokensConsumed: 1 }.to_json,
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
        expect(response.tokens_remaining).to eq(99)
      end

      it 'consumes tokens by path' do
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            headers: {
              'Authorization' => 'Bearer test_key',
              'Content-Type' => 'application/json',
              'Accept' => 'application/json',
              'User-Agent' => 'lightrate-client-ruby/1.0.0'
            },
            body: hash_including(
              path: '/api/v1/emails/send',
              userIdentifier: 'user123',
              tokensRequested: 1
            )
          )
          .to_return(
            status: 200, 
            body: { success: true, tokensRemaining: 99, tokensConsumed: 1 }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        response = client.consume_tokens(
          path: '/api/v1/emails/send',
          user_identifier: 'user123',
          tokens_requested: 1
        )

        expect(response.success).to be true
        expect(response.tokens_remaining).to eq(99)
      end
    end

    describe '#check_tokens' do
      before do
        stub_request(:get, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/check')
          .with(
            headers: {
              'Authorization' => 'Bearer test_key',
              'Accept' => 'application/json',
              'User-Agent' => 'lightrate-client-ruby/1.0.0'
            }
          )
          .to_return(
            status: 200,
            body: {
              available: true,
              tokensRemaining: 100,
              rule: { name: 'Test Rule', refillRate: 10, burstRate: 50 }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'checks tokens by operation' do
        stub_request(:get, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/check')
          .with(
            headers: {
              'Authorization' => 'Bearer test_key',
              'Accept' => 'application/json',
              'User-Agent' => 'lightrate-client-ruby/1.0.0'
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
              tokensRemaining: 100,
              rule: { name: 'Test Rule', refillRate: 10, burstRate: 50 }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        response = client.check_tokens(
          operation: 'send_email',
          user_identifier: 'user123'
        )

        expect(response.available).to be true
        expect(response.tokens_remaining).to eq(100)
      end

      it 'checks tokens by path' do
        stub_request(:get, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/check')
          .with(
            headers: {
              'Authorization' => 'Bearer test_key',
              'Accept' => 'application/json',
              'User-Agent' => 'lightrate-client-ruby/1.0.0'
            },
            query: {
              path: '/api/v1/emails/send',
              userIdentifier: 'user123'
            }
          )
          .to_return(
            status: 200,
            body: {
              available: true,
              tokensRemaining: 100,
              rule: { name: 'Test Rule', refillRate: 10, burstRate: 50 }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        response = client.check_tokens(
          path: '/api/v1/emails/send',
          user_identifier: 'user123'
        )

        expect(response.available).to be true
        expect(response.tokens_remaining).to eq(100)
      end
    end
  end

  describe 'local token bucket functionality' do
    let(:client_with_buckets) do
      described_class.new(
        'test_key',
        default_local_bucket_size: 10,
        bucket_size_configs: {
          operations: {
            'send_email' => 50,
            'send_sms' => 25,
            'send_notification' => 5
          },
          paths: {
            '/api/v1/emails/send' => 30,
            '/api/v1/sms/send' => 15
          }
        }
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
              'User-Agent' => 'lightrate-client-ruby/1.0.0'
            },
            body: hash_including(
              operation: 'send_email',
              userIdentifier: 'user123',
              tokensRequested: 50
            )
          )
            .to_return(
              status: 200,
              body: {
                success: true,
                tokensConsumed: 50,
                tokensRemaining: 950
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
                path: '/api/v1/emails/send',
                userIdentifier: 'user456',
                tokensRequested: 30
              )
            )
            .to_return(
              status: 200,
              body: {
                success: true,
                tokensConsumed: 30,
                tokensRemaining: 970
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          result = client_with_buckets.consume_local_bucket_token(
            path: '/api/v1/emails/send',
            user_identifier: 'user456'
          )

          expect(result.success).to be true
          expect(result.used_local_token).to be false
          expect(result.bucket_status[:tokens_remaining]).to eq(29) # 30 fetched, 1 consumed
          expect(result.bucket_status[:max_tokens]).to eq(30)
        end

        it 'uses default bucket size for unknown operation' do
          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .with(
              body: hash_including(
                operation: 'unknown_operation',
                userIdentifier: 'user789',
                tokensRequested: 10
              )
            )
            .to_return(
              status: 200,
              body: {
                success: true,
                tokensConsumed: 10,
                tokensRemaining: 990
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          result = client_with_buckets.consume_local_bucket_token(
            operation: 'unknown_operation',
            user_identifier: 'user789'
          )

          expect(result.success).to be true
          expect(result.used_local_token).to be false
          expect(result.bucket_status[:tokens_remaining]).to eq(9) # 10 fetched, 1 consumed
          expect(result.bucket_status[:max_tokens]).to eq(10)
        end
      end

      context 'when bucket has tokens (subsequent calls)' do
        before do
          # First call to populate bucket
          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .with(
              body: hash_including(
                operation: 'send_sms',
                userIdentifier: 'user123',
                tokensRequested: 25
              )
            )
            .to_return(
              status: 200,
              body: {
                success: true,
                tokensConsumed: 25,
                tokensRemaining: 975
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
          expect(result.bucket_status[:tokens_remaining]).to eq(23) # 25 - 1 (first call) - 1 (second call)
          expect(result.bucket_status[:max_tokens]).to eq(25)
        end
      end

      context 'when API call fails' do
        before do
          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .to_return(
              status: 200,
              body: {
                error: 'Insufficient tokens available',
                tokensRemaining: 0,
                tokensConsumed: 0
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
                operation: 'send_email',
                userIdentifier: 'user1',
                tokensRequested: 50
              )
            )
            .to_return(
              status: 200,
              body: { success: true, tokensConsumed: 50, tokensRemaining: 950 }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .with(
              body: hash_including(
                operation: 'send_sms',
                userIdentifier: 'user1',
                tokensRequested: 25
              )
            )
            .to_return(
              status: 200,
              body: { success: true, tokensConsumed: 25, tokensRemaining: 975 }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
            .with(
              body: hash_including(
                operation: 'send_email',
                userIdentifier: 'user2',
                tokensRequested: 50
              )
            )
            .to_return(
              status: 200,
              body: { success: true, tokensConsumed: 50, tokensRemaining: 950 }.to_json,
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

          expect(result2.bucket_status[:tokens_remaining]).to eq(24)
          expect(result2.bucket_status[:max_tokens]).to eq(25)

          expect(result3.bucket_status[:tokens_remaining]).to eq(49)
          expect(result3.bucket_status[:max_tokens]).to eq(50)
        end
      end
    end

    describe 'bucket size configuration precedence' do
      let(:client_with_precedence) do
        described_class.new(
          'test_key',
          default_local_bucket_size: 5,
          bucket_size_configs: {
            operations: {
              'send_email' => 100
            },
            paths: {
              '/api/v1/emails/send' => 50
            }
          }
        )
      end

      it 'uses operation-specific size over default' do
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            body: hash_including(
              operation: 'send_email',
              userIdentifier: 'user123',
              tokensRequested: 100
            )
          )
          .to_return(
            status: 200,
            body: { success: true, tokensConsumed: 100, tokensRemaining: 900 }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = client_with_precedence.consume_local_bucket_token(
          operation: 'send_email',
          user_identifier: 'user123'
        )

        expect(result.bucket_status[:max_tokens]).to eq(100)
      end

      it 'uses path-specific size over default' do
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            body: hash_including(
              path: '/api/v1/emails/send',
              userIdentifier: 'user123',
              tokensRequested: 50
            )
          )
          .to_return(
            status: 200,
            body: { success: true, tokensConsumed: 50, tokensRemaining: 950 }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = client_with_precedence.consume_local_bucket_token(
          path: '/api/v1/emails/send',
          user_identifier: 'user123'
        )

        expect(result.bucket_status[:max_tokens]).to eq(50)
      end

      it 'uses default size for unknown operation/path' do
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            body: hash_including(
              operation: 'unknown_operation',
              userIdentifier: 'user123',
              tokensRequested: 5
            )
          )
          .to_return(
            status: 200,
            body: { success: true, tokensConsumed: 5, tokensRemaining: 995 }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        result = client_with_precedence.consume_local_bucket_token(
          operation: 'unknown_operation',
          user_identifier: 'user123'
        )

        expect(result.bucket_status[:max_tokens]).to eq(5)
      end
    end
  end
end
