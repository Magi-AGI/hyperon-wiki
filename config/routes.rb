# -*- encoding : utf-8 -*-

# Manually require MCP API controllers before routing
# Load base controller and concerns first
require Rails.root.join('mod/mcp_api/app/controllers/concerns/rate_limitable.rb')
require Rails.root.join('mod/mcp_api/app/controllers/api/mcp/base_controller.rb')

# Then load all other controllers (including admin namespace)
Dir[Rails.root.join('mod/mcp_api/app/controllers/api/mcp/*_controller.rb')].sort.each do |f|
  require f unless f.include?('base_controller')
end
Dir[Rails.root.join('mod/mcp_api/app/controllers/api/mcp/admin/*_controller.rb')].sort.each do |f|
  require f
end

Decko.application.routes.draw do
  # MCP API routes - must be before Decko::Engine mount to take precedence
  namespace :api do
    namespace :mcp do
      # Health check endpoints (no auth required)
      get 'health', to: 'health#index'
      get 'health/ping', to: 'health#ping'

      # Auth endpoint
      post 'auth', to: 'auth#create'

      # JWKS endpoint (public key distribution)
      get '.well-known/jwks.json', to: 'jwks#show'

      # Types endpoints
      get 'types', to: 'types#index'
      get 'types/:name', to: 'types#show'

      # Jobs endpoints (async operations)
      post 'jobs/spoiler-scan', to: 'jobs#spoiler_scan'

      # Cards endpoints
      resources :cards, param: :name, only: [:index, :show, :create, :update, :destroy] do
        member do
          get :children
          get :referers
          get :nested_in
          get :nests
          get :links
          get :linked_by
          put :rename
          get :search_content
          get :outline
          # History endpoints
          get :history
          get 'history/:act_id', action: :revision, as: :revision
          post :restore
        end

        collection do
          post :batch
        end
      end

      # Trash listing (admin only)
      resources :trash, only: [:index]

      # Render endpoints (Phase 2)
      post 'render', to: 'render#html_to_markdown'
      post 'render/markdown', to: 'render#markdown_to_html'

      # Query endpoint (Phase 3)
      post 'run_query', to: 'query#run'

      # Auto-link endpoint (cross-reference discovery)
      post 'auto_link', to: 'auto_link#create'

      # Validation endpoints
      scope :validation, controller: "validation" do
        post 'tags', action: :validate_tags
        post 'structure', action: :validate_structure
        get 'requirements/:type', action: :requirements
        post 'recommend_structure', action: :recommend_structure
        post 'suggest_improvements', action: :suggest_improvements
      end

      # Admin endpoints (admin role required)
      namespace :admin do
        resources :api_keys, only: [:index, :show, :create, :update, :destroy]

        # Database backup operations
        get 'database/backup', to: 'database#backup'
        get 'database/backup/list', to: 'database#list_backups'
        get 'database/backup/download/:filename', to: 'database#download_backup', constraints: { filename: /[^\/]+/ }
        delete 'database/backup/:filename', to: 'database#delete_backup', constraints: { filename: /[^\/]+/ }
      end
    end
  end
  
  mount Decko::Engine => '/'
end
