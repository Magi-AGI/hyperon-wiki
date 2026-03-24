# frozen_string_literal: true

require "spec_helper"

RSpec.describe Api::Mcp::Admin::DatabaseController, type: :request do
  let(:admin_token) { generate_test_token(role: "admin") }
  let(:user_token) { generate_test_token(role: "user") }
  let(:backup_dir) { Rails.root.join("tmp", "backups") }

  before do
    FileUtils.mkdir_p(backup_dir)
  end

  after do
    # Clean up test backup files
    FileUtils.rm_rf(backup_dir) if Dir.exist?(backup_dir)
  end

  describe "GET /api/mcp/admin/database/backup" do
    context "with admin role" do
      it "creates and returns a database backup" do
        get "/api/mcp/admin/database/backup",
            headers: { "Authorization" => "Bearer #{admin_token}" }

        expect(response).to have_http_status(:success)
        expect(response.headers["Content-Type"]).to eq("application/sql")
        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.body).not_to be_empty
      end

      it "creates backup file with timestamp in name" do
        get "/api/mcp/admin/database/backup",
            headers: { "Authorization" => "Bearer #{admin_token}" }

        expect(response).to have_http_status(:success)
        filename = response.headers["Content-Disposition"].match(/filename="(.+)"/)[1]
        expect(filename).to match(/magi_archive_backup_\d{8}_\d{6}\.sql/)
      end
    end

    context "without admin role" do
      it "denies access to user role" do
        get "/api/mcp/admin/database/backup",
            headers: { "Authorization" => "Bearer #{user_token}" }

        expect(response).to have_http_status(:unauthorized)
      end

      it "denies access without token" do
        get "/api/mcp/admin/database/backup"

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "GET /api/mcp/admin/database/backup/list" do
    before do
      # Create test backup files
      3.times do |i|
        File.write(backup_dir.join("magi_archive_backup_2025120#{i}_120000.sql"), "test backup #{i}")
        sleep 0.01 # Ensure different mtimes
      end
    end

    context "with admin role" do
      it "lists all backup files" do
        get "/api/mcp/admin/database/backup/list",
            headers: { "Authorization" => "Bearer #{admin_token}" }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json["backups"]).to be_an(Array)
        expect(json["total"]).to eq(3)
        expect(json["backup_dir"]).to eq(backup_dir.to_s)
      end

      it "includes file metadata" do
        get "/api/mcp/admin/database/backup/list",
            headers: { "Authorization" => "Bearer #{admin_token}" }

        json = JSON.parse(response.body)
        backup = json["backups"].first

        expect(backup).to have_key("filename")
        expect(backup).to have_key("size")
        expect(backup).to have_key("size_human")
        expect(backup).to have_key("created_at")
        expect(backup).to have_key("modified_at")
        expect(backup).to have_key("age")
      end

      it "sorts backups by modification time (newest first)" do
        get "/api/mcp/admin/database/backup/list",
            headers: { "Authorization" => "Bearer #{admin_token}" }

        json = JSON.parse(response.body)
        filenames = json["backups"].map { |b| b["filename"] }

        # Most recent should be first
        expect(filenames).to eq(filenames.sort.reverse)
      end
    end

    context "when no backups exist" do
      before do
        FileUtils.rm_rf(backup_dir)
      end

      it "returns empty list" do
        get "/api/mcp/admin/database/backup/list",
            headers: { "Authorization" => "Bearer #{admin_token}" }

        json = JSON.parse(response.body)
        expect(json["backups"]).to eq([])
        expect(json["total"]).to eq(0)
      end
    end
  end

  describe "GET /api/mcp/admin/database/backup/download/:filename" do
    let(:test_filename) { "magi_archive_backup_20251203_120000.sql" }

    before do
      File.write(backup_dir.join(test_filename), "test backup content")
    end

    context "with valid filename" do
      it "downloads the specified backup file" do
        get "/api/mcp/admin/database/backup/download/#{test_filename}",
            headers: { "Authorization" => "Bearer #{admin_token}" }

        expect(response).to have_http_status(:success)
        expect(response.body).to eq("test backup content")
        expect(response.headers["Content-Disposition"]).to include(test_filename)
      end
    end

    context "with invalid filename" do
      it "rejects path traversal attempts" do
        get "/api/mcp/admin/database/backup/download/../../../etc/passwd",
            headers: { "Authorization" => "Bearer #{admin_token}" }

        expect(response).to have_http_status(:bad_request)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("invalid_filename")
      end

      it "rejects filenames with special characters" do
        get "/api/mcp/admin/database/backup/download/backup;rm -rf.sql",
            headers: { "Authorization" => "Bearer #{admin_token}" }

        expect(response).to have_http_status(:bad_request)
      end
    end

    context "when file doesn't exist" do
      it "returns not found error" do
        get "/api/mcp/admin/database/backup/download/nonexistent.sql",
            headers: { "Authorization" => "Bearer #{admin_token}" }

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)
        expect(json["error"]).to eq("not_found")
      end
    end
  end

  describe "DELETE /api/mcp/admin/database/backup/:filename" do
    let(:test_filename) { "magi_archive_backup_20251203_120000.sql" }

    before do
      File.write(backup_dir.join(test_filename), "test backup content")
    end

    context "with valid filename" do
      it "deletes the backup file" do
        expect(File.exist?(backup_dir.join(test_filename))).to be true

        delete "/api/mcp/admin/database/backup/#{test_filename}",
               headers: { "Authorization" => "Bearer #{admin_token}" }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)
        expect(json["message"]).to include("deleted successfully")
        expect(json["filename"]).to eq(test_filename)

        expect(File.exist?(backup_dir.join(test_filename))).to be false
      end
    end

    context "with invalid filename" do
      it "rejects path traversal attempts" do
        delete "/api/mcp/admin/database/backup/../../../important_file",
               headers: { "Authorization" => "Bearer #{admin_token}" }

        expect(response).to have_http_status(:bad_request)
      end
    end
  end

  # Helper method to generate test tokens
  def generate_test_token(role:)
    payload = {
      role: role,
      iat: Time.now.to_i,
      exp: (Time.now + 1.hour).to_i
    }
    # Use MessageVerifier for tests
    verifier = ActiveSupport::MessageVerifier.new(Rails.application.secret_key_base)
    verifier.generate(payload)
  end
end
