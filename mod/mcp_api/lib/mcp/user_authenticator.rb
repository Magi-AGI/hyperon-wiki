# frozen_string_literal: true

require "bcrypt"
module Mcp
  # Authenticates Decko users and determines their MCP role
  # Integrates with Decko's Card-based user system
  class UserAuthenticator
    # Authentication error
    class AuthenticationError < StandardError; end

    # Role determination error
    class RoleError < StandardError; end

    # Authenticate a user with username and password
    #
    # @param username [String] The user's login name
    # @param password [String] The user's password
    # @return [Hash] { user: Card, role: String }
    # @raise [AuthenticationError] if authentication fails
    # Authenticate a user with username or email and password
    #
    # @param username [String] Username or email address
    # @param password [String] Password
    # @return [Hash] {user: Card, role: String}
    # @raise [AuthenticationError] if authentication fails
    def self.authenticate(username, password)
      Rails.logger.info("authenticate called with username: #{username}")
      
      # Use Decko's Card::Auth.authenticate which returns the account card
      # It accepts email address and password
      account_card = nil
      
      # Try authenticating with the input as email first
      if username.include?("@")
        Rails.logger.info("Input looks like email, trying Card::Auth.authenticate")
        account_card = Card::Auth.authenticate(username, password)
      end
      
      # If that didn't work, try to find the user and get their email
      unless account_card
        Rails.logger.info("Trying to find user card to get email")
        user_card = find_user_card(username)
        
        if user_card
          # Try to find the account card for this user
          account_card_name = "#{user_card.name}+*account"
          account = Card.find_by_name(account_card_name)
          
          if account
            # Get email from account
            email_card = Card.find_by_name("#{account_card_name}+*email")
            if email_card && email_card.db_content.present?
              email = email_card.db_content
              Rails.logger.info("Found email #{email}, trying Card::Auth.authenticate")
              account_card = Card::Auth.authenticate(email, password)
            end
          end
        end
      end
      
      unless account_card
        Rails.logger.error("Authentication failed - account_card is nil")
        raise AuthenticationError, "Invalid credentials"
      end
      
      Rails.logger.info("Authentication successful! Account card: #{account_card.name}")
      
      # Extract username from account card name (remove +*account suffix)
      username_from_account = account_card.name.sub(/\+\*account$/i, "")
      Rails.logger.info("Extracted username: #{username_from_account}")
      user_card = Card.find_by_name(username_from_account)
      Rails.logger.info("User card lookup result: #{user_card.inspect}")
      
      unless user_card
        Rails.logger.error("Could not find user card for #{username_from_account}")
        raise AuthenticationError, "User card not found"
      end
      
      # Determine MCP role from user permissions
      role = determine_role(user_card)
      
      { user: user_card, role: role }
    end

    
    # Find a user card by username
    #
    # @param username [String] The username
    # @return [Card, nil] The user card or nil
    def self.find_user_card(username)
      # Decko stores users as cards of type "User"
      # Try exact name match first
      user = Card.find_by_name(username)
      return user if user&.type_name == "User"

      # Try case-insensitive name search
      user_type_id = defined?(Card::UserID) ? Card::UserID : Card.find_by_name("User")&.id
      if user_type_id
        user = Card.where("lower(name) = ? AND type_id = ?", username.downcase, user_type_id).first
        return user if user
      end

      # If username looks like an email, search by email subcard
      if username.include?("@")
        # Find all User cards with matching email
        # Email is stored in "Username+*email" subcards
        email_cards = Card.where("lower(db_content) = ?", username.downcase)
                          .where("name LIKE '%+*email'")
        
        email_cards.each do |email_card|
          # Get parent card name (strip +*email)
          parent_name = email_card.name.sub(/\*email$/i, "")
          user = Card.find_by_name(parent_name)
          return user if user&.type_name == "User"
        end
      end

      nil
    rescue StandardError => e
      Rails.logger.error("Error finding user card #{username}: #{e.message}")
      nil
    end

    # Verify password for a user card
    #
    # @param user_card [Card] The user card
    # @param password [String] The password to verify
    # @return [Boolean] True if password is valid
    # Verify password for a user card
    #
    # @param user_card [Card] The user card
    # @param password [String] The password to verify
    # @return [Boolean] True if password is valid
    # Verify password for a user card using Decko's authentication
    #
    # @param user_card [Card] The user card
    # @param password [String] The password to verify
    # @param email [String, nil] Optional email for authentication
    # @return [Boolean] True if password is valid

    def self.determine_role(user_card)
      Rails.logger.info("DEBUG determine_role called for user: #{user_card.name}")
      # Check if user is admin
      return "admin" if admin?(user_card)

      # Check if user is GM
      return "gm" if gm?(user_card)

      # Default to user role
      "user"
    end

    # Check if user has admin permissions
    #
    # @param user_card [Card] The user card
    # @return [Boolean] True if admin
    def self.admin?(user_card)
      # Decko admin check methods:
      # 1. Check if user is in Admin role
      # 2. Check if user has :admin role
      # 3. Check if user has write permission on System cards

      # Method 1: Check role membership
      return true if has_role?(user_card, "Administrator")
      return true if has_role?(user_card, "Admin")

      # Method 2: Check Decko's built-in admin flag
      return true if user_card.respond_to?(:admin?) && user_card.admin?

      # Method 3: Check if user has roles card with admin
      roles_card = Card.find_by_name(user_card.name.to_s + "+*roles")
      Rails.logger.info("DEBUG gm?: roles_card result: #{roles_card.inspect}")
      return true if roles_card&.item_names&.include?("Administrator")

      false
    end

    # Check if user has GM (Game Master) permissions
    #
    # @param user_card [Card] The user card
    # @return [Boolean] True if GM
    def self.gm?(user_card)
      Rails.logger.info("DEBUG gm? called for user: #{user_card.name}")
      # Check if user is in GM role
      return true if has_role?(user_card, "Game Master")
      return true if has_role?(user_card, "GM")

      # Check roles card
      roles_card = Card.find_by_name(user_card.name.to_s + "+*roles")
      Rails.logger.info("DEBUG gm?: roles_card result: #{roles_card.inspect}")
      return true if roles_card && (
        roles_card.item_names.include?("Game Master") ||
        roles_card.item_names.include?("GM")
      )

      false
    end

    # Check if user has a specific role
    #
    # @param user_card [Card] The user card
    # @param role_name [String] The role name to check
    # @return [Boolean] True if user has role
def self.has_role?(user_card, role_name)
      Rails.logger.info("=== MARKER: has_role? method ENTRY POINT ===")
      Rails.logger.info("DEBUG has_role? checking #{role_name} for user: #{user_card.name}")
      
      # Try multiple approaches to access roles (pointer/search type)
      roles_card = nil
      
      # Approach 1: Try user_card.fetch(:roles) - Decko's trait accessor
      begin
        Rails.logger.info("DEBUG Trying user_card.fetch(:roles)")
        roles_card = user_card.fetch(:roles)
        Rails.logger.info("DEBUG fetch(:roles) success: #{roles_card.inspect}")
      rescue => e
        Rails.logger.info("DEBUG fetch(:roles) failed: #{e.message}")
      end
      
      # Approach 2: Try Card[user_card.name, :roles] - compound key lookup
      unless roles_card
        begin
          Rails.logger.info("DEBUG Trying Card[user_card.name, :roles]")
          roles_card = Card[user_card.name, :roles]
          Rails.logger.info("DEBUG Card[name, :roles] success: #{roles_card.inspect}")
        rescue => e
          Rails.logger.info("DEBUG Card[name, :roles] failed: #{e.message}")
        end
      end
      
      # Approach 3: Try Card.find_by_name - traditional lookup
      unless roles_card
        role_card_name = "#{user_card.name}+*roles"
        Rails.logger.info("DEBUG Trying Card.find_by_name('#{role_card_name}')")
        roles_card = Card.find_by_name(role_card_name)
        Rails.logger.info("DEBUG find_by_name result: #{roles_card.inspect}")
      end
      
      return false unless roles_card
      
      # Get role items
      begin
        if roles_card.respond_to?(:item_names)
          item_names = roles_card.item_names
          Rails.logger.info("DEBUG item_names: #{item_names.inspect}")
          result = item_names.include?(role_name)
          Rails.logger.info("DEBUG has_role? result: #{result}")
          return result
        else
          Rails.logger.warn("DEBUG roles_card doesn't respond to item_names")
          return false
        end
      rescue => e
        Rails.logger.error("DEBUG Error getting item_names: #{e.message}")
        return false
      end
    rescue StandardError => e
      Rails.logger.warn("Role check failed for #{user_card.name}: #{e.message}")
      Rails.logger.warn(e.backtrace.join("\n"))
      false
    end

    # Get user's display name
    #
    # @param user_card [Card] The user card
    # @return [String] Display name
    def self.display_name(user_card)
      user_card.name
    end

    # Get user's email (if available)
    #
    # @param user_card [Card] The user card
    # @return [String, nil] Email address
    def self.email(user_card)
      email_card = Card.find_by_name(user_card.name.to_s + "+*email")
      email_card&.db_content
    end
  end
end
