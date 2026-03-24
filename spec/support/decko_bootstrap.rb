# frozen_string_literal: true

# Stub Decko constants that are normally loaded from the database

RSpec.configure do |config|
  config.before(:suite) do
    puts "Stubbing Decko constants for test environment..."
    
    # Stub missing Card constants
    unless defined?(Card::DeckoBotID)
      Card.const_set(:DeckoBotID, 1)
    end
    
    unless defined?(Card::Auth::Current::AnonymousID)
      Card::Auth::Current.const_set(:AnonymousID, 0)
    end
    
    unless defined?(Card::UserID)
      Card.const_set(:UserID, 5)
    end
    
    puts "Decko constants stubbed: DeckoBotID=1, AnonymousID=0, UserID=5"
  end
end
