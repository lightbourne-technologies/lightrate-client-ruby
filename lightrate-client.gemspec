# frozen_string_literal: true

require_relative "lib/lightrate_client/version"

Gem::Specification.new do |spec|
  spec.name = "lightrate-client"
  spec.version = LightrateClient::VERSION
  spec.authors = ["Lightbourne Technologies"]
  spec.email = ["grayden@lightbournetechnologies.ca"]

  spec.summary = "Ruby client for the Lightrate application"
  spec.description = "A comprehensive Ruby gem for interacting with the Lightrate API, providing easy-to-use methods for all Lightrate services."
  spec.homepage = "https://github.com/lightbourne-technologies/lightrate-client-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/lightbourne-technologies/lightrate-client-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/lightbourne-technologies/lightrate-client-ruby/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "faraday", "~> 2.0"
  spec.add_dependency "faraday-retry", "~> 2.0"
  spec.add_dependency "json", "~> 2.0"

  # Development dependencies
  spec.add_development_dependency "bundler", "~> 2.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "rubocop", "~> 1.0"
  spec.add_development_dependency "rubocop-rspec", "~> 2.0"
  spec.add_development_dependency "simplecov", "~> 0.21"
  spec.add_development_dependency "vcr", "~> 6.0"
end
