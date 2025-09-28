#!/usr/bin/env ruby
# frozen_string_literal: true

require 'lightrate_client'

# Create a client with just your API key
client = LightrateClient::Client.new(
  ENV['LIGHTRATE_API_KEY'] || 'your_api_key_here',
  logger: ENV['DEBUG'] ? Logger.new(STDOUT) : nil
)

puts "=== Lightrate Client Example ==="
puts

begin
  # Example 1: Check tokens by operation
  puts "1. Checking tokens for 'send_email' operation..."
  check_response = client.check_tokens(
    operation: 'send_email',
    user_identifier: 'user123'
  )

  puts "   Available: #{check_response.available}"
  puts "   Remaining tokens: #{check_response.remaining_tokens}"
  puts "   Rule: #{check_response.rule.name}"
  puts "   Refill rate: #{check_response.rule.refill_rate}/min"
  puts "   Burst rate: #{check_response.rule.burst_rate}"
  puts

  # Example 2: Consume tokens if available
  if check_response.available
    puts "2. Consuming 1 token for 'send_email' operation..."
    consume_response = client.consume_tokens(
      operation: 'send_email',
      user_identifier: 'user123',
      tokens_requested: 1
    )

    if consume_response.success
      puts "   ✓ Successfully consumed token"
      puts "   Remaining tokens: #{consume_response.remaining_tokens}"
    else
      puts "   ✗ Failed to consume token: #{consume_response.error}"
    end
  else
    puts "2. Skipping token consumption - no tokens available"
  end
  puts

  # Example 3: Check tokens by path
  puts "3. Checking tokens for '/api/v1/emails/send' path..."
  path_check_response = client.check_tokens(
    path: '/api/v1/emails/send',
    user_identifier: 'user123'
  )

  puts "   Available: #{path_check_response.available}"
  puts "   Remaining tokens: #{path_check_response.remaining_tokens}"
  puts

  # Example 4: Using request objects
  puts "4. Using request objects..."
  request = LightrateClient::ConsumeTokensRequest.new(
    operation: 'send_sms',
    user_identifier: 'user456',
    tokens_requested: 2
  )

  if request.valid?
    puts "   Request is valid, attempting to consume tokens..."
    response = client.consume_tokens(request)
    
    if response.success
      puts "   ✓ Successfully consumed #{request.tokens_requested} tokens"
      puts "   Remaining tokens: #{response.remaining_tokens}"
    else
      puts "   ✗ Failed to consume tokens: #{response.error}"
    end
  else
    puts "   ✗ Request is invalid"
  end

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
