# frozen_string_literal: true
#
# Deck-level wiring for the AtomSpace Mirror mod (Lane A).
#
# Decko does NOT auto-load a deck-local mod's Ruby, nor does `decko update` run a mod's db/migrate
# (verified on the dev box 2026-06-15: the mod's lib/card/mod entry and a Rails::Engine were never
# loaded at boot, and decko update's schema-migration step ignores ActiveRecord's migration path).
# So -- exactly like the other deck-local mods (e.g. mcp_api is wired in config/routes.rb) -- the
# mod is wired here:
#   1. require its models + read-consistency so they load at boot;
#   2. put its db/migrate on ActiveRecord's migration path so `rake db:migrate` runs the schema
#      migration. NOTE: the migration runs via `rake db:migrate`, NOT `decko update`
#      (see mod/atomspace_mirror/README.md "Deploy").
#
# Defensive: never block app boot if the mod files are absent (e.g. a branch/deploy without the mod).
begin
  require_relative "../../mod/atomspace_mirror/lib/atomspace_mirror"
rescue LoadError => e
  Rails.logger.warn("[atomspace_mirror] mod code not loaded: #{e.message}")
end

if defined?(ActiveRecord) && Rails.application
  migrate_dir = Rails.root.join("mod", "atomspace_mirror", "db", "migrate").to_s
  if Dir.exist?(migrate_dir)
    # `rake db:migrate` derives its migration paths from config.paths["db/migrate"], NOT from
    # ActiveRecord::Migrator.migrations_paths (verified on dev 2026-06-15). Append to BOTH.
    app_paths = Rails.application.config.paths["db/migrate"]
    app_paths << migrate_dir unless app_paths.to_a.include?(migrate_dir)
    if defined?(ActiveRecord::Migrator) && !ActiveRecord::Migrator.migrations_paths.include?(migrate_dir)
      ActiveRecord::Migrator.migrations_paths << migrate_dir
    end
  end
end
