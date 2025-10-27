#!/usr/bin/env ruby
# frozen_string_literal: true

require 'lightrate_client'

# This example demonstrates making repeated calls to the same HTTP endpoint
# using consume_local_bucket_token. It shows how the local bucket cache
# reduces API calls and improves performance by reusing tokens locally.

# Create a client with default bucket size
# Note: Both API key and application ID are required for all requests
client = LightrateClient::Client.new(
  ENV['LIGHTRATE_API_KEY'] || 'your_api_key_here',
  ENV['LIGHTRATE_APPLICATION_ID'] || 'your_application_id_here',
  default_local_bucket_size: 10,  # Fetch 10 tokens at a time
  logger: ENV['DEBUG'] ? Logger.new(STDOUT) : nil
)

puts "=" * 80
puts "Repeated HTTP Target Example"
puts "=" * 80
puts

# Simulate making 20 calls to the same HTTP endpoint
target_path = '/posts'
target_method = 'GET'
user_id = 'user_12345'

puts "Making 20 calls to #{target_method} #{target_path} for user #{user_id}"
puts
puts "Breakdown:"
puts "  - First call: Will fetch tokens from API (expected to return 10 tokens)"
puts "  - Calls 2-10: Should consume from local bucket (no API calls)"
puts "  - Call 11: Local bucket empty, will fetch more from API"
puts "  - And so on..."
puts
puts "-" * 80
puts

api_calls = 0
cache_hits = 0
call_times = []

20.times do |i|
  call_number = i + 1
  start_time = Time.now
  
  # Make the API call through the client
  result = client.consume_local_bucket_token(
    path: target_path,
    http_method: target_method,
    user_identifier: user_id
  )
  
  elapsed_time = (Time.now - start_time) * 1000  # Convert to milliseconds
  
  call_times << elapsed_time
  
  if result.used_local_token
    cache_hits += 1
    cache_status = "✓ Local cache hit"
  else
    api_calls += 1
    cache_status = "✗ API call made"
  end
  
  if result.bucket_status
    tokens_remaining = result.bucket_status[:tokens_remaining]
    max_tokens = result.bucket_status[:max_tokens]
    bucket_info = " | Bucket: #{tokens_remaining}/#{max_tokens} tokens"
  else
    bucket_info = ""
  end
  
  printf "Call %2d: %s (%.2f ms)%s\n", 
         call_number, 
         cache_status, 
         elapsed_time,
         bucket_info
end

puts
puts "-" * 80
puts "Summary"
puts "-" * 80
puts "Total calls: 20"
puts "API calls made: #{api_calls}"
puts "Cache hits: #{cache_hits}"
puts "Cache hit rate: #{(cache_hits.to_f / 20 * 100).round(1)}%"
puts
puts "Timing statistics:"
puts "  Average time: #{(call_times.sum / call_times.length).round(2)} ms"
puts "  Fastest call: #{call_times.min.round(2)} ms"
puts "  Slowest call: #{call_times.max.round(2)} ms"
puts

# Show the difference between cached and non-cached calls
if call_times.length > 0
  api_call_times = []
  cache_call_times = []
  
  20.times do |i|
    if i == 0 || i % 10 == 0  # API calls happen on first call and when bucket is empty
      api_call_times << call_times[i]
    else
      cache_call_times << call_times[i]
    end
  end
  
  if cache_call_times.any?
    avg_cache_time = cache_call_times.sum / cache_call_times.length
    avg_api_time = api_call_times.sum / api_call_times.length if api_call_times.any?
    
    if avg_api_time
      speedup = avg_api_time / avg_cache_time
      puts "Performance:"
      puts "  Average cached call: #{avg_cache_time.round(2)} ms"
      puts "  Average API call: #{avg_api_time.round(2)} ms"
      puts "  Speed improvement: #{speedup.round(1)}x faster with cache"
    end
  end
end

puts
puts "=" * 80
