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

### Consuming Tokens

```ruby
# Consume tokens by operation
response = client.consume_tokens(
  operation: 'send_email',
  user_identifier: 'user123',
  tokens_requested: 1
)

puts "Tokens consumed: #{response.tokens_consumed}"
puts "Tokens remaining: #{response.tokens_remaining}"
puts "Throttles: #{response.throttles}"
puts "Rule: #{response.rule.name} (ID: #{response.rule.id})"

# Or consume tokens by path
response = client.consume_tokens(
  path: '/api/v1/emails/send',
  user_identifier: 'user123',
  tokens_requested: 1
)

puts "Tokens consumed: #{response.tokens_consumed}"
puts "Tokens remaining: #{response.tokens_remaining}"
puts "Throttles: #{response.throttles}"
puts "Rule: #{response.rule.name} (ID: #{response.rule.id})"
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

puts "Tokens consumed: #{response.tokens_consumed}"
puts "Tokens remaining: #{response.tokens_remaining}"
puts "Throttles: #{response.throttles}"
puts "Rule: #{response.rule.name} (ID: #{response.rule.id})"
```



### Complete Example

```ruby
require 'lightrate_client'

# Create a client with just your API key
client = LightrateClient::Client.new('your_api_key')

begin
  # Consume tokens directly
  consume_response = client.consume_tokens(
    operation: 'send_email',
    user_identifier: 'user123',
    tokens_requested: 1
  )

  puts "Tokens consumed: #{consume_response.tokens_consumed}"
  puts "Tokens remaining: #{consume_response.tokens_remaining}"
  puts "Throttles: #{consume_response.throttles}"
  puts "Rule: #{consume_response.rule.name}"
  # Proceed with your operation

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
