# frozen_string_literal: true

# Add these routes to mcp_routes.rb
# Under the cards resources block, add:
#
#   resources :cards, param: :name, only: [:index, :show, :create, :update, :destroy] do
#     member do
#       get :children
#       get :referers
#       get :linked_by
#       get :nested_in
#       get :nests
#       get :links
#       get :history           # NEW: GET /api/mcp/cards/:name/history
#       get 'history/:act_id', action: :revision, as: :revision  # NEW: GET /api/mcp/cards/:name/history/:act_id
#       post :restore          # NEW: POST /api/mcp/cards/:name/restore
#     end
#     collection do
#       post :batch
#     end
#   end
#
# And add a new top-level resource:
#
#   # Trash listing (admin only)
#   resources :trash, only: [:index]

# For easier merging, here are the exact routes to add:
#
# In the member block:
#   get :history
#   get 'history/:act_id', action: :revision, as: :revision
#   post :restore
#
# At namespace level (outside cards resources):
#   resources :trash, only: [:index]
