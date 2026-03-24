# frozen_string_literal: true

# Phase 2: Database-backed API keys for multi-user access
# Replaces single shared MCP_API_KEY with per-user keys
class CreateMcpApiKeys < ActiveRecord::Migration[7.0]
  def change
    create_table :mcp_api_keys do |t|
      # Security: Store hash only, never plaintext
      t.string :key_hash, null: false
      t.string :key_prefix, null: false, limit: 8  # First 8 chars for display

      # Identification
      t.string :name, null: false                   # Human-readable name
      t.string :description                         # Purpose/notes

      # Permissions
      t.string :allowed_roles, array: true, default: ["user"], null: false
      t.integer :rate_limit_per_hour, default: 1000, null: false

      # Lifecycle
      t.datetime :last_used_at
      t.datetime :expires_at
      t.boolean :active, default: true, null: false

      # Audit trail
      t.string :created_by                          # Admin who created it
      t.string :contact_email                       # Key holder contact

      t.timestamps
    end

    # Indexes for performance
    add_index :mcp_api_keys, :key_hash, unique: true
    add_index :mcp_api_keys, :key_prefix
    add_index :mcp_api_keys, :active
    add_index :mcp_api_keys, :expires_at
    add_index :mcp_api_keys, [:active, :expires_at], name: "index_mcp_api_keys_on_active_and_expires"
  end
end
