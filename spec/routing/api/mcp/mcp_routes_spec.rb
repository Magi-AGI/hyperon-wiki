# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP API Routes", type: :routing do
  # Route specs catch missing routes before they hit production

  describe "Auth routes" do
    it "routes POST /api/mcp/auth to auth#create" do
      expect(post: "/api/mcp/auth").to route_to(
        controller: "api/mcp/auth",
        action: "create"
      )
    end
  end

  describe "JWKS routes" do
    it "routes GET /api/mcp/.well-known/jwks.json to jwks#show" do
      expect(get: "/api/mcp/.well-known/jwks.json").to route_to(
        controller: "api/mcp/jwks",
        action: "show"
      )
    end
  end

  describe "Health routes" do
    it "routes GET /api/mcp/health to health#index" do
      expect(get: "/api/mcp/health").to route_to(
        controller: "api/mcp/health",
        action: "index"
      )
    end

    it "routes GET /api/mcp/health/ping to health#ping" do
      expect(get: "/api/mcp/health/ping").to route_to(
        controller: "api/mcp/health",
        action: "ping"
      )
    end
  end

  describe "Jobs routes" do
    it "routes POST /api/mcp/jobs/spoiler-scan to jobs#spoiler_scan" do
      # This would have caught the missing route error!
      expect(post: "/api/mcp/jobs/spoiler-scan").to route_to(
        controller: "api/mcp/jobs",
        action: "spoiler_scan"
      )
    end
  end

  describe "Cards routes" do
    it "routes GET /api/mcp/cards to cards#index" do
      expect(get: "/api/mcp/cards").to route_to(
        controller: "api/mcp/cards",
        action: "index"
      )
    end

    it "routes GET /api/mcp/cards/:name to cards#show" do
      expect(get: "/api/mcp/cards/TestCard").to route_to(
        controller: "api/mcp/cards",
        action: "show",
        name: "TestCard"
      )
    end

    it "routes POST /api/mcp/cards to cards#create" do
      expect(post: "/api/mcp/cards").to route_to(
        controller: "api/mcp/cards",
        action: "create"
      )
    end

    it "routes PATCH /api/mcp/cards/:name to cards#update" do
      expect(patch: "/api/mcp/cards/TestCard").to route_to(
        controller: "api/mcp/cards",
        action: "update",
        name: "TestCard"
      )
    end

    it "routes DELETE /api/mcp/cards/:name to cards#destroy" do
      expect(delete: "/api/mcp/cards/TestCard").to route_to(
        controller: "api/mcp/cards",
        action: "destroy",
        name: "TestCard"
      )
    end

    it "routes POST /api/mcp/cards/batch to cards#batch" do
      expect(post: "/api/mcp/cards/batch").to route_to(
        controller: "api/mcp/cards",
        action: "batch"
      )
    end

    it "routes GET /api/mcp/cards/:name/children to cards#children" do
      expect(get: "/api/mcp/cards/TestCard/children").to route_to(
        controller: "api/mcp/cards",
        action: "children",
        name: "TestCard"
      )
    end

    it "routes GET /api/mcp/cards/:name/referers to cards#referers" do
      expect(get: "/api/mcp/cards/TestCard/referers").to route_to(
        controller: "api/mcp/cards",
        action: "referers",
        name: "TestCard"
      )
    end
  end

  describe "Query routes" do
    it "routes POST /api/mcp/run_query to query#run" do
      expect(post: "/api/mcp/run_query").to route_to(
        controller: "api/mcp/query",
        action: "run"
      )
    end
  end

  describe "Render routes" do
    it "routes POST /api/mcp/render to render#html_to_markdown" do
      expect(post: "/api/mcp/render").to route_to(
        controller: "api/mcp/render",
        action: "html_to_markdown"
      )
    end

    it "routes POST /api/mcp/render/markdown to render#markdown_to_html" do
      expect(post: "/api/mcp/render/markdown").to route_to(
        controller: "api/mcp/render",
        action: "markdown_to_html"
      )
    end
  end

  describe "Admin routes" do
    describe "Database" do
      it "routes GET /api/mcp/admin/database/backup to admin/database#backup" do
        expect(get: "/api/mcp/admin/database/backup").to route_to(
          controller: "api/mcp/admin/database",
          action: "backup"
        )
      end

      it "routes GET /api/mcp/admin/database/backup/list to admin/database#list_backups" do
        expect(get: "/api/mcp/admin/database/backup/list").to route_to(
          controller: "api/mcp/admin/database",
          action: "list_backups"
        )
      end
    end

    describe "API Keys" do
      it "routes GET /api/mcp/admin/api_keys to admin/api_keys#index" do
        expect(get: "/api/mcp/admin/api_keys").to route_to(
          controller: "api/mcp/admin/api_keys",
          action: "index"
        )
      end

      it "routes POST /api/mcp/admin/api_keys to admin/api_keys#create" do
        expect(post: "/api/mcp/admin/api_keys").to route_to(
          controller: "api/mcp/admin/api_keys",
          action: "create"
        )
      end
    end
  end

  describe "AtomSpace card-scoped quarantine routes (B3 admin surface)" do
    it "routes GET quarantine/card/:card_id to atomspace_mirror#quarantine_index" do
      expect(get: "/api/mcp/atomspace_mirror/quarantine/card/5").to route_to(
        controller: "api/mcp/atomspace_mirror",
        action: "quarantine_index",
        card_id: "5"
      )
    end

    it "routes POST quarantine/card/:card_id/delete to atomspace_mirror#quarantine_delete" do
      expect(post: "/api/mcp/atomspace_mirror/quarantine/card/5/delete").to route_to(
        controller: "api/mcp/atomspace_mirror",
        action: "quarantine_delete",
        card_id: "5"
      )
    end

    it "does not route a non-numeric card_id to the quarantine actions" do
      expect(get: "/api/mcp/atomspace_mirror/quarantine/card/abc")
        .not_to route_to(controller: "api/mcp/atomspace_mirror", action: "quarantine_index")
      expect(post: "/api/mcp/atomspace_mirror/quarantine/card/abc/delete").not_to be_routable
    end

    it "retires the pre-REV5 global quarantine forms" do
      expect(get: "/api/mcp/atomspace_mirror/quarantine")
        .not_to route_to(controller: "api/mcp/atomspace_mirror", action: "quarantine_index")
      expect(post: "/api/mcp/atomspace_mirror/quarantine/5/delete").not_to be_routable
    end

    # Regression: Rails' implicit `(.:format)` segment is applied BEFORE the :card_id constraint,
    # so without `format: false` a request for `card/1.9` parsed as card_id="1" + format="9" and the
    # admin surface silently answered for card 1 instead of rejecting an ambiguous target. Verified
    # against the running local stack: GET card/1.9, card/2.json and card/1.xml each returned 200
    # for the truncated id before `format: false` was added.
    it "refuses a format-suffixed card_id instead of silently truncating it" do
      expect(get: "/api/mcp/atomspace_mirror/quarantine/card/1.9")
        .not_to route_to(controller: "api/mcp/atomspace_mirror", action: "quarantine_index")
      expect(get: "/api/mcp/atomspace_mirror/quarantine/card/2.json")
        .not_to route_to(controller: "api/mcp/atomspace_mirror", action: "quarantine_index")
      expect(post: "/api/mcp/atomspace_mirror/quarantine/card/1.9/delete").not_to be_routable
    end
  end
end
