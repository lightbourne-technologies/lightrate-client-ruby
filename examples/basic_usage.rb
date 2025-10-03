#!/usr/bin/env ruby
# frozen_string_literal: true

require 'lightrate_client'

# Create a client with local token bucket configuration
client = LightrateClient::Client.new(
  ENV['LIGHTRATE_API_KEY'] || 'your_api_key_here',
  local_token_bucket_size: 50,  # Store up to 50 tokens locally per bucket
  logger: ENV['DEBUG'] ? Logger.new(STDOUT) : nil
)

puts "=== Lightrate Client with Local Token Buckets ==="
puts

begin
  # Example 1: Using consume_local_bucket_token (first call - will fetch from API)
  puts "1. First call to consume_local_bucket_token (will fetch from API):"
  result1 = client.consume_local_bucket_token(
    operation: 'send_email',
    user_identifier: 'user123'
  )

  puts "   Success: #{result1[:success]}"
  puts "   Used local token: #{result1[:used_local_token]}"
  puts "   Bucket status: #{result1[:bucket_status]}"
  puts

  # Example 2: Using consume_local_bucket_token (second call - will use local bucket)
  puts "2. Second call to consume_local_bucket_token (will use local bucket):"
  result2 = client.consume_local_bucket_token(
    operation: 'send_email',
    user_identifier: 'user123'
  )

  puts "   Success: #{result2[:success]}"
  puts "   Used local token: #{result2[:used_local_token]}"
  puts "   Bucket status: #{result2[:bucket_status]}"
  puts

  # Example 3: Different user/operation gets separate bucket
  puts "3. Different user/operation (creates new bucket):"
  result3 = client.consume_local_bucket_token(
    operation: 'send_sms',
    user_identifier: 'user456'
  )

  puts "   Success: #{result3[:success]}"
  puts "   Used local token: #{result3[:used_local_token]}"
  puts "   Bucket status: #{result3[:bucket_status]}"
  puts

  # Example 4: Direct API call using consume_tokens
  puts "4. Direct API call using consume_tokens:"
  api_response = client.consume_tokens(
    operation: 'send_notification',
    user_identifier: 'user789',
    tokens_requested: 3
  )

  puts "   Success: #{api_response['success']}"
  puts "   Tokens consumed: #{api_response['tokensConsumed']}"
  puts "   Tokens remaining: #{api_response['tokensRemaining']}"
  puts

rescue LightrateClient::UnauthorizedError => e
  puts "❌ Authentication failed: #{e.message}"
  puts "   Please check your API key"
rescue LightrateClient::ForbiddenError => e
  puts "❌ Access denied: #{e.message}"
  puts "   Please check your subscription status"
rescue LightrateClient::TooManyRequestsError => e
  puts "⚠️  Rate limited: #{e.message}"
  puts "   Please wait before making more requests"
rescue LightrateClient::NotFoundError => e
  puts "❌ Rule not found: #{e.message}"
  puts "   Please check your operation/path configuration"
rescue LightrateClient::APIError => e
  puts "❌ API Error (#{e.status_code}): #{e.message}"
rescue LightrateClient::NetworkError => e
  puts "❌ Network error: #{e.message}"
  puts "   Please check your internet connection"
rescue LightrateClient::TimeoutError => e
  puts "❌ Request timed out: #{e.message}"
rescue => e
  puts "❌ Unexpected error: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end

puts
puts "=== Example Complete ==="
