# frozen_string_literal: true

require "spec_helper"

RSpec.describe Api::Mcp::ValidationController, type: :request do
  let(:user_token) { generate_test_token(role: "user") }

  describe "POST /api/mcp/validation/tags" do
    context "with valid parameters" do
      it "validates tags for a card type" do
        post "/api/mcp/validation/tags",
             params: {
               type: "Species",
               tags: ["Game", "Alien"]
             },
             headers: { "Authorization" => "Bearer #{user_token}" }

        expect(response).to have_http_status(:success)
        json = JSON.parse(response.body)

        expect(json).to have_key("valid")
        expect(json).to have_key("errors")
        expect(json).to have_key("warnings")
        expect(json).to have_key("required_tags")
        expect(json).to have_key("suggested_tags")
        expect(json).to have_key("provided_tags")
      end

      it "returns validation errors for missing required tags" do
        # Stub tag fetching to return predictable results
        allow_any_instance_of(Api::Mcp::ValidationController)
          .to receive(:fetch_available_tags).and_return(["GM", "Game", "Species"])

        post "/api/mcp/validation/tags",
             params: {
               type: "Game Master Document",
               tags: ["Game"],
               name: "Secret Plot+GM"
             },
             headers: { "Authorization" => "Bearer #{user_token}" }

        json = JSON.parse(response.body)

        expect(json["valid"]).to be false
        expect(json["errors"]).to include(a_string_matching(/Missing required tags.*GM/))
      end

      it "returns warnings for missing suggested tags" do
        allow_any_instance_of(Api::Mcp::ValidationController)
          .to receive(:fetch_available_tags).and_return(["GM", "Game", "Species"])

        post "/api/mcp/validation/tags",
             params: {
               type: "Species",
               tags: []
             },
             headers: { "Authorization" => "Bearer #{user_token}" }

        json = JSON.parse(response.body)

        expect(json["valid"]).to be true # No required tags
        expect(json["warnings"]).not_to be_empty
      end

      it "suggests tags based on content" do
        post "/api/mcp/validation/tags",
             params: {
               type: "Article",
               tags: [],
               content: "This is a game master only document with spoilers"
             },
             headers: { "Authorization" => "Bearer #{user_token}" }

        json = JSON.parse(response.body)

        # Should suggest GM tag based on content
        expect(json["warnings"].join(" ")).to match(/GM/i)
      end

      it "validates naming conventions" do
        post "/api/mcp/validation/tags",
             params: {
               type: "Game Master Document",
               tags: [],
               name: "Secret Plot+GM"
             },
             headers: { "Authorization" => "Bearer #{user_token}" }

        json = JSON.parse(response.body)

        # Should warn about missing GM tag when name includes +GM
        expect(json["warnings"]).to include(a_string_matching(/\+GM.*GM.*tag/i))
      end
    end

    context "with missing parameters" do
      it "requires type parameter" do
        post "/api/mcp/validation/tags",
             params: { tags: ["Game"] },
             headers: { "Authorization" => "Bearer #{user_token}" }

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)
        expect(json["message"]).to include("type")
      end
    end
  end

  describe "POST /api/mcp/validation/structure" do
    it "validates card structure" do
      post "/api/mcp/validation/structure",
           params: {
             type: "Species",
             name: "Vulcans",
             has_children: true,
             children_names: ["Vulcans+traits", "Vulcans+description"]
           },
           headers: { "Authorization" => "Bearer #{user_token}" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json).to have_key("valid")
      expect(json).to have_key("errors")
      expect(json).to have_key("warnings")
      expect(json).to have_key("required_children")
      expect(json).to have_key("suggested_children")
    end

    it "returns errors for missing required children" do
      post "/api/mcp/validation/structure",
           params: {
             type: "Species",
             name: "Vulcans",
             has_children: false
           },
           headers: { "Authorization" => "Bearer #{user_token}" }

      json = JSON.parse(response.body)

      # If Species has required children, should have errors
      if json["required_children"].any?
        expect(json["valid"]).to be false
        expect(json["errors"]).not_to be_empty
      end
    end

    it "returns warnings for missing suggested children" do
      post "/api/mcp/validation/structure",
           params: {
             type: "Species",
             name: "Vulcans",
             has_children: true,
             children_names: []
           },
           headers: { "Authorization" => "Bearer #{user_token}" }

      json = JSON.parse(response.body)

      # Species should have suggested children
      expect(json["warnings"]).not_to be_empty
    end
  end

  describe "GET /api/mcp/validation/requirements/:type" do
    it "returns requirements for a card type" do
      allow_any_instance_of(Api::Mcp::ValidationController)
        .to receive(:fetch_available_tags).and_return(["GM", "Game", "Species", "Faction"])

      get "/api/mcp/validation/requirements/Species",
          headers: { "Authorization" => "Bearer #{user_token}" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json).to have_key("required_tags")
      expect(json).to have_key("suggested_tags")
      expect(json).to have_key("required_children")
      expect(json).to have_key("suggested_children")

      # Species should suggest children
      expect(json["suggested_children"]).to include("*traits", "*description", "*culture")
    end

    it "returns only existing tags from wiki" do
      # Stub with limited tag set
      allow_any_instance_of(Api::Mcp::ValidationController)
        .to receive(:fetch_available_tags).and_return(["Game", "Species"])

      get "/api/mcp/validation/requirements/Species",
          headers: { "Authorization" => "Bearer #{user_token}" }

      json = JSON.parse(response.body)

      # Should only suggest tags that exist
      expect(json["suggested_tags"]).to all(be_in(["Game", "Species"]))
    end

    it "returns defaults for unknown card type" do
      get "/api/mcp/validation/requirements/UnknownType",
          headers: { "Authorization" => "Bearer #{user_token}" }

      json = JSON.parse(response.body)

      expect(json["required_tags"]).to eq([])
      expect(json["suggested_tags"]).to eq([])
      expect(json["required_children"]).to eq([])
      expect(json["suggested_children"]).to eq([])
    end
  end

  describe "POST /api/mcp/validation/recommend_structure" do
    it "returns comprehensive structure recommendations" do
      allow_any_instance_of(Api::Mcp::ValidationController)
        .to receive(:fetch_available_tags).and_return(["Game", "Species", "Alien"])

      post "/api/mcp/validation/recommend_structure",
           params: {
             type: "Species",
             name: "Vulcans",
             tags: ["Game"],
             content: "Logical species from planet Vulcan"
           },
           headers: { "Authorization" => "Bearer #{user_token}" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json).to have_key("card_type")
      expect(json).to have_key("card_name")
      expect(json).to have_key("children")
      expect(json).to have_key("tags")
      expect(json).to have_key("naming")
      expect(json).to have_key("summary")

      expect(json["card_type"]).to eq("Species")
      expect(json["card_name"]).to eq("Vulcans")
    end

    it "recommends child cards with metadata" do
      allow_any_instance_of(Api::Mcp::ValidationController)
        .to receive(:fetch_available_tags).and_return(["Game", "Species"])

      post "/api/mcp/validation/recommend_structure",
           params: {
             type: "Species",
             name: "Vulcans",
             tags: [],
             content: ""
           },
           headers: { "Authorization" => "Bearer #{user_token}" }

      json = JSON.parse(response.body)
      children = json["children"]

      expect(children).to be_an(Array)
      expect(children).not_to be_empty

      child = children.first
      expect(child).to have_key("name")
      expect(child).to have_key("type")
      expect(child).to have_key("purpose")
      expect(child).to have_key("priority")

      # Name should include parent
      expect(child["name"]).to start_with("Vulcans+")
    end

    it "categorizes tag recommendations" do
      allow_any_instance_of(Api::Mcp::ValidationController)
        .to receive(:fetch_available_tags).and_return(["GM", "Game", "Species"])

      post "/api/mcp/validation/recommend_structure",
           params: {
             type: "Game Master Document",
             name: "Secret Plot",
             tags: [],
             content: "GM-only spoiler content"
           },
           headers: { "Authorization" => "Bearer #{user_token}" }

      json = JSON.parse(response.body)
      tags = json["tags"]

      expect(tags).to have_key("required")
      expect(tags).to have_key("suggested")
      expect(tags).to have_key("content_based")

      # GM Document requires GM tag
      expect(tags["required"]).to include("GM")
      # Content mentions GM, should suggest GM tag
      expect(tags["content_based"]).to include("GM")
    end
  end

  describe "POST /api/mcp/validation/suggest_improvements" do
    let(:species_card) { create_test_card("Vulcans", type: "Species") }

    before do
      # Create test card in database
      allow(Card).to receive(:fetch).with("Vulcans").and_return(species_card)
    end

    it "analyzes existing card and suggests improvements" do
      post "/api/mcp/validation/suggest_improvements",
           params: { name: "Vulcans" },
           headers: { "Authorization" => "Bearer #{user_token}" }

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)

      expect(json).to have_key("card_name")
      expect(json).to have_key("card_type")
      expect(json).to have_key("missing_children")
      expect(json).to have_key("missing_tags")
      expect(json).to have_key("suggested_additions")
      expect(json).to have_key("naming_issues")
      expect(json).to have_key("summary")

      expect(json["card_name"]).to eq("Vulcans")
    end

    it "returns not found for non-existent card" do
      allow(Card).to receive(:fetch).with("Nonexistent").and_return(nil)

      post "/api/mcp/validation/suggest_improvements",
           params: { name: "Nonexistent" },
           headers: { "Authorization" => "Bearer #{user_token}" }

      expect(response).to have_http_status(:not_found)
    end
  end

  # Helper methods
  def generate_test_token(role:)
    payload = {
      role: role,
      iat: Time.now.to_i,
      exp: (Time.now + 1.hour).to_i
    }
    verifier = ActiveSupport::MessageVerifier.new(Rails.application.secret_key_base)
    verifier.generate(payload)
  end

  def create_test_card(name, type:)
    card = double("Card")
    allow(card).to receive(:name).and_return(name)
    allow(card).to receive(:type_name).and_return(type)
    allow(card).to receive(:children).and_return([])
    allow(card).to receive(:fetch).with(trait: "tags").and_return(nil)
    card
  end
end
