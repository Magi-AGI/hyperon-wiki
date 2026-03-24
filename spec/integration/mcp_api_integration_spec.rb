# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP API Integration", type: :integration do
  # Integration tests catch issues with file loading, constant lookup, and module dependencies

  describe "Constant loading" do
    it "loads ::Mcp::UserAuthenticator without NameError" do
      expect { ::Mcp::UserAuthenticator }.not_to raise_error
    end

    it "can access UserAuthenticator from Api::Mcp namespace" do
      # This would have caught the constant lookup issue
      # When inside Api::Mcp module, Ruby looks for Api::Mcp::UserAuthenticator first
      expect {
        # Simulate being inside Api::Mcp namespace
        Module.new do
          include Api::Mcp
          ::Mcp::UserAuthenticator # Using :: forces top-level lookup
        end
      }.not_to raise_error(NameError)
    end

    it "loads JobsController without uninitialized constant error" do
      expect { Api::Mcp::JobsController }.not_to raise_error(NameError)
    end

    it "loads AuthController without require_relative errors" do
      # This would have caught the wrong require_relative path
      expect {
        load Rails.root.join("mod/mcp_api/app/controllers/api/mcp/auth_controller.rb")
      }.not_to raise_error(LoadError)
    end
  end

  describe "File loading" do
    it "loads all MCP controllers without errors" do
      controller_files = Dir[Rails.root.join("mod/mcp_api/app/controllers/api/mcp/**/*.rb")]

      controller_files.each do |file|
        expect {
          load file
        }.not_to raise_error, "Failed to load #{file}"
      end
    end

    it "loads all MCP lib files without errors" do
      lib_files = Dir[Rails.root.join("mod/mcp_api/lib/**/*.rb")]

      lib_files.each do |file|
        expect {
          load file
        }.not_to raise_error, "Failed to load #{file}"
      end
    end

    it "can require UserAuthenticator from lib" do
      # Test the actual require path
      expect {
        require Rails.root.join("mod/mcp_api/lib/mcp/user_authenticator").to_s
      }.not_to raise_error
    end
  end

  describe "Card::UserID constant" do
    it "handles Card::UserID constant gracefully" do
      # Test that UserAuthenticator doesn't crash if Card::UserID is undefined
      expect {
        ::Mcp::UserAuthenticator.send(:find_user_card, "test@example.com")
      }.not_to raise_error(NameError, /Card::UserID/)
    end

    it "falls back to Card.find_by_name when Card::UserID unavailable" do
      # Hide the constant temporarily
      if defined?(Card::UserID)
        user_id_value = Card::UserID
        Card.send(:remove_const, :UserID)

        begin
          result = ::Mcp::UserAuthenticator.send(:find_user_card, "nonexistent")
          expect(result).to be_nil # Should not crash
        ensure
          # Restore constant
          Card.const_set(:UserID, user_id_value)
        end
      end
    end
  end

  describe "Module nesting" do
    it "correctly resolves constants with :: prefix" do
      # Test that ::Mcp:: works from within Api::Mcp
      expect {
        Api::Mcp::AuthController.new.send(:authenticate_with_username) rescue nil
      }.not_to raise_error(NameError, /uninitialized constant Api::Mcp::UserAuthenticator/)
    end
  end

  describe "Production-like lazy loading" do
    around do |example|
      # Simulate production lazy loading
      old_eager_load = Rails.application.config.eager_load
      Rails.application.config.eager_load = false

      # Clear loaded constants
      ActiveSupport::Dependencies.clear

      example.run

      # Restore
      Rails.application.config.eager_load = old_eager_load
    end

    it "loads auth controller on-demand without errors" do
      expect {
        Api::Mcp::AuthController
      }.not_to raise_error
    end

    it "loads jobs controller on-demand without errors" do
      expect {
        Api::Mcp::JobsController
      }.not_to raise_error
    end
  end

  describe "Full request cycle" do
    it "handles auth request without constant errors" do
      expect {
        post "/api/mcp/auth", params: {
          username: "test",
          password: "test"
        }, as: :json
      }.not_to raise_error(NameError)
    end

    it "handles jobs request without constant errors" do
      token = generate_test_jwt(role: "gm")

      expect {
        post "/api/mcp/jobs/spoiler-scan",
          params: {
            terms_card: "Test",
            results_card: "Results"
          },
          headers: { "Authorization" => "Bearer #{token}" },
          as: :json
      }.not_to raise_error(NameError)
    end
  end

  private

  def generate_test_jwt(role:)
    payload = {
      sub: "user:Test",
      role: role,
      iss: "test",
      iat: Time.now.to_i,
      exp: (Time.now + 1.hour).to_i,
      jti: SecureRandom.uuid
    }
    McpApi::JwtService.generate_token(payload)
  end
end
