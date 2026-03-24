# frozen_string_literal: true

module McpApi
  class Engine < ::Rails::Engine
    isolate_namespace McpApi
    
    # Add mod's app directory to autoload paths BEFORE they get frozen
    config.autoload_paths << root.join('app/controllers').to_s
    config.eager_load_paths << root.join('app/controllers').to_s
    
    # Ensure controllers are loaded
    config.before_initialize do
      Rails.autoloaders.main.push_dir(root.join('app/controllers'))
    end
  end
end
