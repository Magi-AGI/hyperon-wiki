# frozen_string_literal: true

# Mount MCP API routes - append to existing routes instead of redrawing
Rails.application.routes.append do
  namespace :api do
    namespace :mcp do
      # Auth endpoint
      post "auth", to: "auth#create"

      # JWKS endpoint (public key distribution)
      get ".well-known/jwks.json", to: "jwks#show"

      # Types endpoints
      get "types", to: "types#index"
      get "types/:name", to: "types#show"

      # Cards endpoints
      resources :cards, param: :name, only: [:index, :show, :create, :update, :destroy] do
        member do
          get :children
        end

        collection do
          post :batch
        end
      end

      # Render endpoints (Phase 2)
      namespace :render do
        post "/", to: "render#html_to_markdown", as: :html_to_markdown
        post "markdown", to: "render#markdown_to_html"
      end
    end
  end
end
