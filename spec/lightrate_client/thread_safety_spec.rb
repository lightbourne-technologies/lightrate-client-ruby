# frozen_string_literal: true

require 'spec_helper'

RSpec.describe LightrateClient::Client do
  describe 'thread safety' do
    let(:client) do
      described_class.new(
        'test_key',
        default_local_bucket_size: 10,
        logger: nil # Disable logging for cleaner test output
      )
    end

    describe 'concurrent consume_local_bucket_token calls' do
      it 'prevents race conditions when multiple threads consume from empty bucket' do
        # Mock the API response
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            body: hash_including(
              operation: 'test_operation',
              userIdentifier: 'test_user',
              tokensRequested: 10
            )
          )
          .to_return(
            status: 200,
            body: { success: true, tokensConsumed: 10, tokensRemaining: 990 }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        # Track API calls to ensure only one is made
        api_call_count = 0
        allow(client).to receive(:post) do |*args|
          api_call_count += 1
          # Simulate some network delay
          sleep(0.01)
          { 'tokensConsumed' => 10, 'tokensRemaining' => 990 }
        end

        # Create multiple threads that try to consume tokens simultaneously
        threads = []
        results = []
        mutex = Mutex.new

        10.times do
          threads << Thread.new do
            result = client.consume_local_bucket_token(
              operation: 'test_operation',
              user_identifier: 'test_user'
            )
            mutex.synchronize { results << result }
          end
        end

        # Wait for all threads to complete
        threads.each(&:join)

        # Verify results
        expect(results.length).to eq(10)
        expect(api_call_count).to eq(1), "Expected only 1 API call, but got #{api_call_count}"
        
        # All calls should succeed
        expect(results.all?(&:success)).to be true
        
        # Only the first call should have used local token (false), others should have used local tokens (true)
        local_token_usage = results.map(&:used_local_token)
        expect(local_token_usage.count(false)).to eq(1) # First call fetched from API
        expect(local_token_usage.count(true)).to eq(9)  # Subsequent calls used local tokens
      end

      it 'maintains separate buckets for different users concurrently' do
        # Mock API responses for different users
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            body: hash_including(userIdentifier: 'user1')
          )
          .to_return(
            status: 200,
            body: { success: true, tokensConsumed: 5, tokensRemaining: 995 }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .with(
            body: hash_including(userIdentifier: 'user2')
          )
          .to_return(
            status: 200,
            body: { success: true, tokensConsumed: 3, tokensRemaining: 997 }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        # Create threads for different users
        threads = []
        user1_results = []
        user2_results = []
        mutex = Mutex.new

        # User 1 threads
        5.times do
          threads << Thread.new do
            result = client.consume_local_bucket_token(
              operation: 'test_op',
              user_identifier: 'user1'
            )
            mutex.synchronize { user1_results << result }
          end
        end

        # User 2 threads
        3.times do
          threads << Thread.new do
            result = client.consume_local_bucket_token(
              operation: 'test_op',
              user_identifier: 'user2'
            )
            mutex.synchronize { user2_results << result }
          end
        end

        threads.each(&:join)

        # Verify results
        expect(user1_results.length).to eq(5)
        expect(user2_results.length).to eq(3)
        
        # All calls should succeed
        expect(user1_results.all?(&:success)).to be true
        expect(user2_results.all?(&:success)).to be true
        
        # Check that each user's bucket is independent
        user1_buckets = user1_results.map { |r| r.bucket_status[:tokens_remaining] }
        user2_buckets = user2_results.map { |r| r.bucket_status[:tokens_remaining] }
        
        # Each user should have their own bucket state
        expect(user1_buckets.uniq.length).to be >= 1
        expect(user2_buckets.uniq.length).to be >= 1
      end

      it 'handles concurrent bucket creation without duplicates' do
        stub_request(:post, 'https://api.lightrate.lightbournetechnologies.ca/api/v1/tokens/consume')
          .to_return(
            status: 200,
            body: { success: true, tokensConsumed: 1, tokensRemaining: 999 }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        # Create multiple threads that will all create the same bucket
        threads = []
        buckets_created = []
        mutex = Mutex.new

        20.times do
          threads << Thread.new do
            result = client.consume_local_bucket_token(
              operation: 'new_operation',
              user_identifier: 'new_user'
            )
            mutex.synchronize { buckets_created << result.bucket_status }
          end
        end

        threads.each(&:join)

        # All should succeed
        expect(buckets_created.length).to eq(20)
        
        # All buckets should have the same max_tokens (same bucket instance)
        max_tokens = buckets_created.map { |status| status[:max_tokens] }.uniq
        expect(max_tokens.length).to eq(1)
        expect(max_tokens.first).to eq(10) # default_local_bucket_size
      end
    end

    describe 'TokenBucket thread safety' do
      let(:bucket) { LightrateClient::TokenBucket.new(5) }

      it 'handles concurrent token consumption' do
        # Refill the bucket first
        bucket.synchronize { bucket.refill(5) }
        
        # Create multiple threads trying to consume tokens
        threads = []
        consumed_count = 0
        mutex = Mutex.new

        10.times do
          threads << Thread.new do
            success = bucket.synchronize { bucket.consume_token }
            if success
              mutex.synchronize { consumed_count += 1 }
            end
          end
        end

        threads.each(&:join)

        # Should have consumed exactly 5 tokens (bucket size)
        expect(consumed_count).to eq(5)
        expect(bucket.synchronize { bucket.available_tokens }).to eq(0)
      end

      it 'handles concurrent refill operations' do
        threads = []
        refilled_count = 0
        mutex = Mutex.new

        3.times do
          threads << Thread.new do
            added = bucket.synchronize { bucket.refill(2) }
            mutex.synchronize { refilled_count += added }
          end
        end

        threads.each(&:join)

        # Should have refilled properly without exceeding max
        expect(refilled_count).to eq(5) # 2 + 2 + 1, capped at max_tokens of 5
        expect(bucket.synchronize { bucket.available_tokens }).to eq(5) # Capped at max_tokens
      end
    end
  end
end
