# Lightrate Client Ruby

A Ruby gem for interacting with the Lightrate token management API, providing easy-to-use methods for consuming and checking tokens.

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
  config.base_url = 'https://api.lightrate.lightbournetechnologies.ca' # optional, defaults to production
  config.timeout = 30 # optional, defaults to 30 seconds
  config.retry_attempts = 3 # optional, defaults to 3
  config.logger = Logger.new(STDOUT) # optional, for request logging
end
```

### Basic Usage

```ruby
# Simple usage - just pass your API key
client = LightrateClient::Client.new('your_api_key')

# Or use the convenience method
client = LightrateClient.new_client('your_api_key')

# With additional options
client = LightrateClient::Client.new('your_api_key', 
  timeout: 60
)

# Or configure globally and use the default client
LightrateClient.configure do |config|
  config.api_key = 'your_api_key'
end
client = LightrateClient.client
```

### Consuming Tokens

```ruby
# Consume tokens by operation
response = client.consume_tokens(
  operation: 'send_email',
  user_identifier: 'user123',
  tokens_requested: 1
)

# Or consume tokens by path
response = client.consume_tokens(
  path: '/api/v1/emails/send',
  user_identifier: 'user123',
  tokens_requested: 1
)

if response.success
  puts "Tokens consumed successfully. Remaining: #{response.remaining_tokens}"
else
  puts "Failed to consume tokens: #{response.error}"
end
```

#### Using Request Objects

```ruby
# Create a consume tokens request
request = LightrateClient::ConsumeTokensRequest.new(
  operation: 'send_email',
  user_identifier: 'user123',
  tokens_requested: 1
)

# Consume tokens
response = client.consume_tokens_with_request(request)

if response.success
  puts "Tokens consumed successfully. Remaining: #{response.remaining_tokens}"
else
  puts "Failed to consume tokens: #{response.error}"
end
```

### Checking Tokens

```ruby
# Check tokens by operation
response = client.check_tokens(
  operation: 'send_email',
  user_identifier: 'user123'
)

# Or check tokens by path
response = client.check_tokens(
  path: '/api/v1/emails/send',
  user_identifier: 'user123'
)

puts "Available: #{response.available}"
puts "Remaining tokens: #{response.remaining_tokens}"
puts "Rule: #{response.rule.name} (refill: #{response.rule.refill_rate}, burst: #{response.rule.burst_rate})"
```

#### Using Request Objects

```ruby
# Create a check tokens request
request = LightrateClient::CheckTokensRequest.new(
  operation: 'send_email',
  user_identifier: 'user123'
)

# Check tokens
response = client.check_tokens_with_request(request)

puts "Available: #{response.available}"
puts "Remaining tokens: #{response.remaining_tokens}"
puts "Rule: #{response.rule.name} (refill: #{response.rule.refill_rate}, burst: #{response.rule.burst_rate})"
```

### Complete Example

```ruby
require 'lightrate_client'

# Create a client with just your API key
client = LightrateClient::Client.new('your_api_key')

begin
  # Check if tokens are available before attempting to consume
  check_response = client.check_tokens(
    operation: 'send_email',
    user_identifier: 'user123'
  )

  if check_response.available
    puts "Tokens available: #{check_response.remaining_tokens}"
    
    # Consume tokens
    consume_response = client.consume_tokens(
      operation: 'send_email',
      user_identifier: 'user123',
      tokens_requested: 1
    )

    if consume_response.success
      puts "Successfully consumed tokens. Remaining: #{consume_response.remaining_tokens}"
      # Proceed with your operation
    else
      puts "Failed to consume tokens: #{consume_response.error}"
    end
  else
    puts "No tokens available. Remaining: #{check_response.remaining_tokens}"
    # Handle rate limiting
  end

rescue LightrateClient::UnauthorizedError => e
  puts "Authentication failed: #{e.message}"
rescue LightrateClient::TooManyRequestsError => e
  puts "Rate limited: #{e.message}"
rescue LightrateClient::APIError => e
  puts "API Error (#{e.status_code}): #{e.message}"
rescue LightrateClient::NetworkError => e
  puts "Network error: #{e.message}"
end
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
