#!/usr/bin/env ruby
# frozen_string_literal: true

require 'lightrate_client'

# Create a client with per-operation/path bucket size configuration
client = LightrateClient::Client.new(
  ENV['LIGHTRATE_API_KEY'] || 'your_api_key_here',
  default_local_bucket_size: 20,  # Default bucket size
  bucket_size_configs: {
    operations: {
      'send_email' => 100,      # Email operations get larger buckets
      'send_sms' => 50,         # SMS operations get medium buckets
      'send_notification' => 10 # Notifications get smaller buckets
    },
    paths: {
      '/api/v1/emails/send' => 75,  # Specific path gets custom size
      '/api/v1/sms/send' => 25      # Another specific path
    }  
  },
  logger: ENV['DEBUG'] ? Logger.new(STDOUT) : nil
)

puts "=== Lightrate Client with Local Token Buckets ==="
puts

begin
  # Example 1: Email operation (gets 100 token bucket)
  puts "1. Email operation (bucket size: 100):"
  result1 = client.consume_local_bucket_token(
    operation: 'send_email',
    user_identifier: 'user123'
  )

  puts "   Success: #{result1[:success]}"
  puts "   Used local token: #{result1[:used_local_token]}"
  puts "   Bucket status: #{result1[:bucket_status]}"
  puts

  # Example 2: SMS operation (gets 50 token bucket)
  puts "2. SMS operation (bucket size: 50):"
  result2 = client.consume_local_bucket_token(
    operation: 'send_sms',
    user_identifier: 'user123'
  )

  puts "   Success: #{result2[:success]}"
  puts "   Used local token: #{result2[:used_local_token]}"
  puts "   Bucket status: #{result2[:bucket_status]}"
  puts

  # Example 3: Notification operation (gets 10 token bucket)
  puts "3. Notification operation (bucket size: 10):"
  result3 = client.consume_local_bucket_token(
    operation: 'send_notification',
    user_identifier: 'user123'
  )

  puts "   Success: #{result3[:success]}"
  puts "   Used local token: #{result3[:used_local_token]}"
  puts "   Bucket status: #{result3[:bucket_status]}"
  puts

  # Example 4: Path-based configuration
  puts "4. Path-based operation (bucket size: 75):"
  result4 = client.consume_local_bucket_token(
    path: '/api/v1/emails/send',
    http_method: 'POST',
    user_identifier: 'user456'
  )

  puts "   Success: #{result4[:success]}"
  puts "   Used local token: #{result4[:used_local_token]}"
  puts "   Bucket status: #{result4[:bucket_status]}"
  puts

  # Example 5: Pattern-based path (admin path gets 5 token bucket)
  puts "5. Admin path operation (bucket size: 5):"
  result5 = client.consume_local_bucket_token(
    path: '/api/v1/admin/users/123/notify',
    http_method: 'POST',
    user_identifier: 'admin_user'
  )

  puts "   Success: #{result5[:success]}"
  puts "   Used local token: #{result5[:used_local_token]}"
  puts "   Bucket status: #{result5[:bucket_status]}"
  puts

  # Example 6: Different HTTP methods for same path
  puts "6. Different HTTP methods for same path:"
  result6a = client.consume_local_bucket_token(
    path: '/api/v1/users',
    http_method: 'GET',
    user_identifier: 'user123'
  )
  result6b = client.consume_local_bucket_token(
    path: '/api/v1/users',
    http_method: 'POST',
    user_identifier: 'user123'
  )
  
  puts "   GET /api/v1/users - Success: #{result6a[:success]}"
  puts "   POST /api/v1/users - Success: #{result6b[:success]}"
  puts "   (These create separate buckets due to different HTTP methods)"
  puts

  # Example 7: Direct API call using consume_tokens
  puts "7. Direct API call using consume_tokens:"
  api_response = client.consume_tokens(
    operation: 'send_notification',
    user_identifier: 'user789',
    tokens_requested: 3
  )

  puts "   Success: #{api_response['success']}"
  puts "   Tokens consumed: #{api_response['tokensConsumed']}"
  puts "   Tokens remaining: #{api_response['tokensRemaining']}"
  puts

  # Example 7: Show all bucket statuses with their sizes
  puts "7. All bucket statuses (showing different sizes per operation/path):"
  all_statuses = client.all_bucket_statuses
  if all_statuses.any?
    all_statuses.each do |key, status|
      puts "   #{key}: #{status[:available_tokens]}/#{status[:max_tokens]} tokens"
    end
  else
    puts "   No local buckets created yet"
  end
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
