source "http://rubygems.org"

gem "decko", "~> 0.20.0"
gem "nokogiri"


# DATABASE
# Decko currently supports MySQL (best tested), PostgreSQL (well tested), and SQLite
# (not well tested).
# Use mysql as the database for Active Record
gem "pg", "~> 1.5"


# WEBSERVER
# To run a simple deck at localhost:3000, you can use thin (recommended), unicorn,
# or (Rails" default) Webrick
gem "thin"
# gem "unicorn"


# CARD MODS
# The easiest way to change card behaviors is with card mods. To install a mod:
#
#   1. add `gem "card-mod-MODNAME"` below
#   2. run `bundle update` to install the code
#   3. run `decko update` to make any needed changes to your deck
#
# The "defaults" includes a lot of functionality that is needed in standard decks.
gem "card-mod-defaults"

# MCP API dependencies
gem "bcrypt" # Password hashing for user authentication
gem "jwt" # RS256 JWT authentication (Phase 2)
gem "kramdown" # Proper Markdown parsing (Phase 2)
gem "reverse_markdown" # HTML to Markdown conversion (Phase 2)


# BACKGROUND
# A background gem is needed to run tasks like sending notifications in a background
# process.
# See https://github.com/decko-commons/decko/tree/main/card-mod-delayed_job
# for additional configuration details.
# gem "card-mod-delayed_job"


# MONKEYS
# You can also create your own mods. Mod developers (or "Monkeys") will want some
# additional gems to support development and testing.
# gem "card-mod-monkey", group: :development
gem "decko-rspec", group: :test
# gem "decko-cucumber", group: :cucumber
# gem "decko-cypress", group: :cypress
# gem "decko-profile", group: :profile



