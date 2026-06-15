# frozen_string_literal: true

module AtomspaceMirror
  # Rails engine for the mod. Its job in Slice 1 is to put the mod's db/migrate directory on the
  # application's migration path, so `decko update` / `rake db:migrate` run the schema migration.
  #
  # Decko does NOT auto-discover a mod's db/migrate (verified on the dev box 2026-06-15: the
  # application's migration path is just the deck-root "db/migrate", and mod/mcp_api's own
  # db/migrate never ran). This is the standard Rails-engine migration-append pattern; mcp_api's
  # engine omits it (it only registers app/controllers), which is why its migration never executed.
  class Engine < ::Rails::Engine
    initializer "atomspace_mirror.append_migrations" do |app|
      # Skip if this engine somehow IS the host app (defensive; never true for a mod engine).
      next if app.root.to_s == root.to_s

      migrate_dir = root.join("db", "migrate").to_s
      app.config.paths["db/migrate"] << migrate_dir
      unless ActiveRecord::Migrator.migrations_paths.include?(migrate_dir)
        ActiveRecord::Migrator.migrations_paths << migrate_dir
      end
    end
  end
end
