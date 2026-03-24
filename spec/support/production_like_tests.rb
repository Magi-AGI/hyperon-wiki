# frozen_string_literal: true

# Production-like test configuration
# This configuration simulates production behavior to catch deployment issues

RSpec.configure do |config|
  # Tag for production-like tests
  config.before(:each, :production_like) do
    # Disable eager loading to simulate production lazy loading
    @original_eager_load = Rails.application.config.eager_load
    Rails.application.config.eager_load = false

    # Clear autoloaded constants to force re-loading
    ActiveSupport::Dependencies.clear
  end

  config.after(:each, :production_like) do
    # Restore eager loading
    Rails.application.config.eager_load = @original_eager_load
  end

  # Integration test configuration
  config.before(:each, :integration) do
    # Integration tests run against real endpoints
    # Ensure we're not stubbing HTTP requests
    WebMock.allow_net_connect! if defined?(WebMock)
  end

  config.after(:each, :integration) do
    # Restore WebMock stubbing
    WebMock.disable_net_connect!(
      allow_localhost: true
    ) if defined?(WebMock)
  end
end

# Helper to run specs in production-like environment
# Usage: run_in_production_mode { expect(...).to ... }
def run_in_production_mode
  old_env = Rails.env
  old_eager_load = Rails.application.config.eager_load

  begin
    # Simulate production
    Rails.env = ActiveSupport::StringInquirer.new("production")
    Rails.application.config.eager_load = false # Lazy load to catch issues

    # Clear constants
    ActiveSupport::Dependencies.clear

    yield
  ensure
    # Restore
    Rails.env = ActiveSupport::StringInquirer.new(old_env)
    Rails.application.config.eager_load = old_eager_load
  end
end

# Helper to test constant lookup from nested modules
# Usage: test_constant_lookup("Api::Mcp", "::Mcp::UserAuthenticator")
def test_constant_lookup(from_module, constant_name)
  mod = from_module.constantize
  mod.const_get(constant_name, false) # false = don't inherit
rescue NameError => e
  # If it fails with uninitialized constant, that's the bug!
  raise e
end
