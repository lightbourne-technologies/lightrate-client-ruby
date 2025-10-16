# Lightrate Client Ruby

A Ruby gem for interacting with the Lightrate token management API, providing easy-to-use methods for consuming tokens.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'lightrate-client'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install lightrate-client
```

## Usage

### Configuration

Configure the client with your API credentials:

```ruby
require 'lightrate_client'

LightrateClient.configure do |config|
  config.api_key = 'your_api_key'
  config.application_id = 'your_application_id' # required
  config.timeout = 30 # optional, defaults to 30 seconds
  config.retry_attempts = 3 # optional, defaults to 3
  config.logger = Logger.new(STDOUT) # optional, for request logging
end
```

### Basic Usage

```ruby
# Simple usage - pass your API key and application ID
client = LightrateClient::Client.new('your_api_key', 'your_application_id')

# Or use the convenience method
client = LightrateClient.new_client('your_api_key', 'your_application_id')

# With additional options
client = LightrateClient::Client.new('your_api_key', 'your_application_id',
  timeout: 60
)

# Or configure globally and use the default client
LightrateClient.configure do |config|
  config.api_key = 'your_api_key'
  config.application_id = 'your_application_id'
end
client = LightrateClient.client
```

### Token Consumption Methods

The Lightrate Client provides two methods for consuming tokens, each with different performance characteristics:

#### 🚀 Recommended: Local Token Buckets (`consume_local_bucket_token`)

**Use this method for high-frequency token consumption.** It maintains local token buckets that are refilled in batches from the API, dramatically reducing the number of HTTP requests.

```ruby
# Configure client with default bucket size
client = LightrateClient::Client.new(
  'your_api_key', 
  'your_application_id',
  default_local_bucket_size: 20  # Default bucket size for all operations
)

# Consume tokens using local buckets (fast, reduces API calls)
response = client.consume_local_bucket_token(
  operation: 'send_email',
  user_identifier: 'user123'
)

puts "Success: #{response.success}"
puts "Used local token: #{response.used_local_token}"
puts "Bucket status: #{response.bucket_status}"

# Or consume by path
response = client.consume_local_bucket_token(
  path: '/api/v1/emails/send',
  http_method: 'POST',
  user_identifier: 'user123'
)
```

**Benefits of Local Buckets:**
- ⚡ **Fast**: Most token consumption happens locally without HTTP requests
- 🔄 **Efficient**: Batches token requests to reduce API calls by 95%+
- 🛡️ **Resilient**: Continues working even with temporary API outages
- 🎯 **Configurable**: Customizable bucket sizes for your application needs

#### 🌐 Direct API Calls (`consume_tokens`)

**Use this method for occasional token consumption or when you need immediate API feedback.**

```ruby
# Direct API call - makes HTTP request every time
response = client.consume_tokens(
  operation: 'send_email',
  user_identifier: 'user123',
  tokens_requested: 1
)

puts "Tokens consumed: #{response.tokens_consumed}"
puts "Tokens remaining: #{response.tokens_remaining}"
puts "Throttles: #{response.throttles}"
puts "Rule: #{response.rule.name} (ID: #{response.rule.id})"
```

**When to use Direct API Calls:**
- 🔍 **Debugging**: When you need immediate API feedback
- 📊 **Monitoring**: For applications that rarely consume tokens
- 🎛️ **Control**: When you need precise control over token requests
- 🔄 **Legacy**: For compatibility with existing code

### Method Comparison

| Feature | Local Buckets | Direct API |
|---------|---------------|------------|
| **Speed** | ⚡ Very Fast | 🐌 Network dependent |
| **API Calls** | 📉 Minimal (95%+ reduction) | 📈 Every request |
| **Resilience** | 🛡️ High (works offline briefly) | 🔗 Requires network |
| **Feedback** | 📊 Bucket status only | 📋 Full API response |
| **Best For** | High-frequency usage | Occasional usage |

### Performance Benefits

**Local Token Buckets dramatically improve performance:**

- **95%+ reduction in API calls** - Instead of making an HTTP request for every token consumption, tokens are fetched in batches
- **Sub-millisecond response times** - Local token consumption is nearly instant
- **Better reliability** - Continues working even during brief API outages
- **Reduced bandwidth costs** - Fewer HTTP requests mean lower network usage

**Example Performance Comparison:**
```ruby
# ❌ Slow: Direct API calls
1000.times do
  client.consume_tokens(operation: 'send_email', user_identifier: 'user123', tokens_requested: 1)
  # Each call: ~100-200ms network latency
end
# Total: 1000 API calls, ~100-200 seconds

# ✅ Fast: Local buckets
1000.times do
  client.consume_local_bucket_token(operation: 'send_email', user_identifier: 'user123')
  # Each call: ~0.1ms local operation
end
# Total: ~1 API call, ~0.1 seconds
```

### When to Use Each Method

**Use Local Buckets when:**
- 🚀 Building high-performance applications
- 📧 Sending bulk emails, SMS, or notifications
- 🔄 Processing webhooks or background jobs
- 📊 Handling user-facing requests that need fast response times
- 🏭 Running production applications with high token usage

**Use Direct API when:**
- 🔍 Debugging or testing rate limiting
- 📊 Building monitoring dashboards
- 🎛️ Need immediate feedback on token consumption
- 🔄 Migrating from existing implementations
- 📱 Building low-frequency applications (fewer than 10 requests/minute)



### Complete Example: High-Performance Token Consumption

```ruby
require 'lightrate_client'

# Create a client with default bucket size
client = LightrateClient::Client.new(
  ENV['LIGHTRATE_API_KEY'] || 'your_api_key',
  ENV['LIGHTRATE_APPLICATION_ID'] || 'your_application_id',
  default_local_bucket_size: 50  # All operations use this bucket size
)

begin
  # First call: Fetches 50 tokens from API and consumes 1 locally
  response1 = client.consume_local_bucket_token(
    operation: 'send_email',
    user_identifier: 'user123'
  )
  
  puts "First call - Success: #{response1.success}"
  puts "Used local token: #{response1.used_local_token}"
  puts "Bucket status: #{response1.bucket_status}"
  
  # Second call: Consumes from local bucket (no API call!)
  response2 = client.consume_local_bucket_token(
    operation: 'send_email',
    user_identifier: 'user123'
  )
  
  puts "Second call - Success: #{response2.success}"
  puts "Used local token: #{response2.used_local_token}"
  puts "Bucket status: #{response2.bucket_status}"
  
  # Example with path-based consumption
  response3 = client.consume_local_bucket_token(
    path: '/api/v1/emails/send',
    http_method: 'POST',
    user_identifier: 'user123'
  )
  
  puts "Path-based call - Success: #{response3.success}"
  puts "Bucket status: #{response3.bucket_status}"
  
  # Proceed with your operations...

rescue LightrateClient::UnauthorizedError => e
  puts "❌ Authentication failed: #{e.message}"
rescue LightrateClient::TooManyRequestsError => e
  puts "⚠️  Rate limited: #{e.message}"
rescue LightrateClient::APIError => e
  puts "❌ API Error (#{e.status_code}): #{e.message}"
rescue LightrateClient::NetworkError => e
  puts "❌ Network error: #{e.message}"
end
```

### Advanced Configuration

```ruby
# For applications with very high token consumption
client = LightrateClient::Client.new(
  'your_api_key',
  'your_application_id',
  default_local_bucket_size: 500,  # Large default bucket for all operations
  timeout: 60,                      # Longer timeout for large bucket requests
  retry_attempts: 5,                # More retries for reliability
  logger: Logger.new(STDOUT)        # Enable request logging
)
```

## Error Handling

The gem provides comprehensive error handling with specific exception types:

```ruby
begin
  client.users
rescue LightrateClient::UnauthorizedError => e
  puts "Authentication failed: #{e.message}"
rescue LightrateClient::NotFoundError => e
  puts "Resource not found: #{e.message}"
rescue LightrateClient::APIError => e
  puts "API Error (#{e.status_code}): #{e.message}"
rescue LightrateClient::NetworkError => e
  puts "Network error: #{e.message}"
rescue LightrateClient::TimeoutError => e
  puts "Request timed out: #{e.message}"
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/lightbourne-technologies/lightrate-client-ruby. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/lightbourne-technologies/lightrate-client-ruby/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Lightrate Client Ruby project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/lightbourne-technologies/lightrate-client-ruby/blob/main/CODE_OF_CONDUCT.md).
