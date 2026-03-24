# frozen_string_literal: true

# Set Rails environment before loading Rails
ENV["RAILS_ENV"] ||= "test"

# Load the Rails application (this will autoload everything)
require File.expand_path("../config/environment", __dir__)

# Load RSpec and Rails integration
require "rspec/rails"

# Require support files
Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

# Load MCP API test helpers
require_relative "mcp_api/spec_helper"

# Configure RSpec
RSpec.configure do |config|
  # Use transactional fixtures
  config.use_transactional_fixtures = true

  # Infer spec type from file location
  config.infer_spec_type_from_file_location!

  # Filter Rails backtrace
  config.filter_rails_from_backtrace!

  # Disable monkey patching
  config.disable_monkey_patching!

  # Use expect syntax
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Run specs in random order
  config.order = :random
  Kernel.srand config.seed
end
