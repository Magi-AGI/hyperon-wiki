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
          # File/Image upload endpoints
          post :upload
          get :file_url
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

      # Upload endpoint - glob route for card names with special characters
      post "cards/*name/upload", to: "cards#upload", format: false, constraints: { name: /.*/ }

      # AtomSpace mirror read API (Lane C, Level 9). Controller: Api::Mcp::AtomspaceMirrorController.
      # Gated by the mcp:atomspace:read scope; quarantine additionally requires mcp:admin.
      scope :atomspace_mirror do
        get  "query_atoms",           to: "atomspace_mirror#query_atoms"
        get  "get_card_atom",         to: "atomspace_mirror#get_card_atom"
        get  "get_card_provenance",   to: "atomspace_mirror#get_card_provenance"
        get  "list_references",       to: "atomspace_mirror#list_references"
        get  "list_atoms_by_type",    to: "atomspace_mirror#list_atoms_by_type"
        get  "atom_types",            to: "atomspace_mirror#atom_types"
        get  "atom_count_by_type",    to: "atomspace_mirror#atom_count_by_type"
        get  "space_stats",           to: "atomspace_mirror#space_stats"
        get  "quarantine",            to: "atomspace_mirror#quarantine_index"
        post "quarantine/:id/delete", to: "atomspace_mirror#quarantine_delete"
      end

      # Render endpoints (Phase 2)
      # Use scope instead of namespace - controller is at Api::Mcp::RenderController
      scope :render do
        post "/", to: "render#html_to_markdown", as: :render_html_to_markdown
        post "markdown", to: "render#markdown_to_html", as: :render_markdown_to_html
      end
    end
  end
end
