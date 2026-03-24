# frozen_string_literal: true

require "securerandom"

namespace :mcp do
  desc "Idempotently create MCP service accounts (mcp-user, mcp-gm, mcp-admin) with role-appropriate permissions"
  task setup_roles: :environment do
    accounts = [
      {
        name: ENV.fetch("MCP_USER_NAME", "mcp-user"),
        email: ENV["MCP_USER_EMAIL"],
        password: ENV["MCP_USER_PASSWORD"],
        role: :user
      },
      {
        name: ENV.fetch("MCP_GM_NAME", "mcp-gm"),
        email: ENV["MCP_GM_EMAIL"],
        password: ENV["MCP_GM_PASSWORD"],
        role: :gm
      },
      {
        name: ENV.fetch("MCP_ADMIN_NAME", "mcp-admin"),
        email: ENV["MCP_ADMIN_EMAIL"],
        password: ENV["MCP_ADMIN_PASSWORD"],
        role: :admin
      }
    ]

    missing_creds = accounts.select { |a| a[:email].to_s.empty? || a[:password].to_s.empty? }
    if missing_creds.any?
      puts "⚠️  Skipping creation for accounts missing email/password:"
      missing_creds.each do |acct|
        puts "  - #{acct[:name]} (role: #{acct[:role]})"
      end
      puts "Set MCP_*_EMAIL and MCP_*_PASSWORD env vars to create missing accounts."
    end

    Card::Auth.as_bot do
      user_type_id = Card.fetch("User").id
      created = []
      skipped = []
      role_assignments = []

      # Fetch Decko role cards for assignment
      admin_role = Card.fetch("Administrator")

      accounts.each do |acct|
        existing = Card[acct[:name]]
        if existing
          skipped << { name: acct[:name], id: existing.id, status: :exists }
          # Still attempt role assignment for existing accounts
          assign_role(existing, acct[:role], admin_role, role_assignments)
          next
        end

        if acct[:email].to_s.empty? || acct[:password].to_s.empty?
          skipped << { name: acct[:name], id: nil, status: :missing_credentials }
          next
        end

        password = acct[:password]
        # Decko stores account info on subcards; create user with account/email/password/status.
        card = Card.create!(
          name: acct[:name],
          type_id: user_type_id,
          subcards: {
            "+*account+*email" => acct[:email],
            "+*account+*password" => password,
            "+*account+*status" => "active"
          }
        )
        created << { name: acct[:name], id: card.id }

        # Assign to appropriate Decko role
        assign_role(card, acct[:role], admin_role, role_assignments)
      rescue StandardError => e
        skipped << { name: acct[:name], id: nil, status: :error, error: e.message }
      end

      puts "✅ Created: #{created.map { |c| "#{c[:name]}(##{c[:id]})" }.join(', ')}" unless created.empty?
      unless skipped.empty?
        puts "ℹ️  Skipped: #{skipped.map { |s| "#{s[:name]}(#{s[:status]})" }.join(', ')}"
        skipped.each do |s|
          puts "   #{s[:name]}: #{s[:error]}" if s[:error]
        end
      end
      puts "🔐 Role assignments: #{role_assignments.join(', ')}" unless role_assignments.empty?
    end
  end

  # Helper to assign service account to appropriate Decko role
  def assign_role(user_card, mcp_role, admin_role, role_assignments)
    case mcp_role
    when :admin
      # Add to Administrator role members
      if admin_role
        members_card = Card.fetch("#{admin_role.name}+*members", new: {})
        current_members = members_card.item_names || []

        unless current_members.include?(user_card.name)
          members_card.items = current_members + [user_card.name]
          members_card.save!
          role_assignments << "#{user_card.name} → Administrator"
        end
      else
        puts "⚠️  Warning: Administrator role not found; mcp-admin will have limited permissions"
      end
    when :gm
      # Add to Game Master role members
      gm_role = Card.fetch("Game Master")
      if gm_role
        members_card = Card.fetch("#{gm_role.name}+*members", new: {})
        current_members = members_card.item_names || []

        unless current_members.include?(user_card.name)
          members_card.items = current_members + [user_card.name]
          members_card.save!
          role_assignments << "#{user_card.name} → Game Master"
        end
      else
        puts "⚠️  Warning: Game Master role not found; mcp-gm will have limited permissions"
        role_assignments << "#{user_card.name} → GM (role not found)"
      end
    when :user
      # User role: default permissions (no special role assignment needed)
      role_assignments << "#{user_card.name} → User (default)"
    end
  rescue StandardError => e
    puts "⚠️  Failed to assign role for #{user_card.name}: #{e.message}"
  end
  end
