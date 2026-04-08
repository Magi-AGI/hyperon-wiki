# frozen_string_literal: true

# Mount MCP API routes - append to existing routes instead of redrawing
Rails.application.routes.append do
  namespace :api do
    namespace :mcp do
      # Auth endpoint
      post "auth", to: "auth#create"
      # Note: debug endpoint at POST auth/debug doesn't load correctly in Decko's routing
      # Use server logs for role detection debugging instead

      # JWKS endpoint (public key distribution)
      get ".well-known/jwks.json", to: "jwks#show"

      # Types endpoints
      get "types", to: "types#index"
      get "types/:name", to: "types#show"

      # Tags endpoints
      get "tags", to: "tags#index"
      get "tags/:tag_name/cards", to: "tags#cards"
      post "tags/suggest", to: "tags#suggest"

      # Cards endpoints
      resources :cards, param: :name, only: [:index, :show, :create, :update, :destroy] do
        member do
          get :children
          # Relationship endpoints
          get :referers
          get :linked_by
          get :nested_in
          get :nests
          get :links
          # History endpoints (Phase 4)
          get :history
          get "history/:act_id", action: :revision, as: :revision
          post :restore
        end

        collection do
          post :batch
        end
      end

      # Trash listing (admin only, Phase 4)
      resources :trash, only: [:index]

      # Rename endpoint - defined separately to handle complex card names
      # Using glob constraint to capture full path including encoded characters
      put "cards/*name/rename", to: "cards#rename", format: false, constraints: { name: /.*/ }

      # Render endpoints (Phase 2)
      # Use scope instead of namespace - controller is at Api::Mcp::RenderController
      scope :render do
        post "/", to: "render#html_to_markdown", as: :render_html_to_markdown
        post "markdown", to: "render#markdown_to_html", as: :render_markdown_to_html
      end
    end
  end
end
