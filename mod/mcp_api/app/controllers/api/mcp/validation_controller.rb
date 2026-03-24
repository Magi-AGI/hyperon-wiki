# frozen_string_literal: true

module Api
  module Mcp
    # Validation controller for card validation operations
    class ValidationController < BaseController
      # POST /api/mcp/validation/tags
      # Validate tags for a card based on its type and content
      def validate_tags
        card_type = params[:type]
        tags = Array(params[:tags])
        content = params[:content] || ""
        card_name = params[:name]

        return render_error("validation_error", "Missing type parameter") unless card_type

        validation_result = perform_tag_validation(card_type, tags, content, card_name)

        render json: validation_result
      end

      # POST /api/mcp/validation/structure
      # Validate card structure based on type
      def validate_structure
        card_type = params[:type]
        card_name = params[:name]
        has_children = params[:has_children] || false
        children_names = Array(params[:children_names])

        return render_error("validation_error", "Missing type parameter") unless card_type

        validation_result = perform_structure_validation(card_type, card_name, has_children, children_names)

        render json: validation_result
      end

      # GET /api/mcp/validation/requirements/:type
      # Get tag and structure requirements for a card type
      def requirements
        card_type = params[:type]

        return render_error("validation_error", "Missing type parameter") unless card_type

        requirements = get_type_requirements(card_type)

        render json: requirements
      end

      # POST /api/mcp/validation/recommend_structure
      # Get comprehensive structure recommendations for a card
      def recommend_structure
        card_type = params[:type]
        card_name = params[:name]
        tags = Array(params[:tags])
        content = params[:content] || ""

        return render_error("validation_error", "Missing type parameter") unless card_type

        recommendations = generate_structure_recommendations(card_type, card_name, tags, content)

        render json: recommendations
      end

      # POST /api/mcp/validation/suggest_improvements
      # Suggest improvements for an existing card structure
      def suggest_improvements
        card_name = params[:name]

        return render_error("validation_error", "Missing name parameter") unless card_name

        card = Card::Auth.as(current_account.name) do
          Card.fetch(card_name)
        end
        return render_error("not_found", "Card '#{card_name}' not found") unless card

        improvements = analyze_card_and_suggest_improvements(card)

        render json: improvements
      end

      private

      def perform_tag_validation(card_type, tags, content, card_name)
        errors = []
        warnings = []
        required_tags = []
        suggested_tags = []

        # Get requirements for this card type
        type_requirements = get_type_requirements(card_type)
        required_tags = type_requirements[:required_tags] || []
        suggested_tags = type_requirements[:suggested_tags] || []

        # Check required tags
        missing_required = required_tags - tags
        if missing_required.any?
          errors << "Missing required tags: #{missing_required.join(', ')}"
        end

        # Check suggested tags
        missing_suggested = suggested_tags - tags
        if missing_suggested.any?
          warnings << "Consider adding suggested tags: #{missing_suggested.join(', ')}"
        end

        # Content-based tag suggestions
        content_suggestions = suggest_tags_from_content(content, tags)
        if content_suggestions.any?
          warnings << "Content suggests additional tags: #{content_suggestions.join(', ')}"
        end

        # Naming convention checks
        if card_name
          naming_warnings = check_naming_conventions(card_name, card_type, tags)
          warnings.concat(naming_warnings)
        end

        {
          valid: errors.empty?,
          errors: errors,
          warnings: warnings,
          required_tags: required_tags,
          suggested_tags: suggested_tags,
          provided_tags: tags
        }
      end

      def perform_structure_validation(card_type, card_name, has_children, children_names)
        errors = []
        warnings = []

        # Get requirements for this card type
        type_requirements = get_type_requirements(card_type)
        required_children = type_requirements[:required_children] || []
        suggested_children = type_requirements[:suggested_children] || []

        # Check required children
        if required_children.any? && !has_children
          errors << "This card type requires child cards: #{required_children.join(', ')}"
        elsif required_children.any?
          missing_required = required_children.reject do |child_pattern|
            # Convert pattern like "*background" to regex that matches "CardName+background"
            pattern_regex = child_pattern_to_regex(child_pattern, card_name)
            children_names.any? { |name| name.match?(pattern_regex) }
          end

          if missing_required.any?
            errors << "Missing required child cards: #{missing_required.join(', ')}"
          end
        end

        # Check suggested children
        if suggested_children.any? && has_children
          missing_suggested = suggested_children.reject do |child_pattern|
            # Convert pattern like "*background" to regex that matches "CardName+background"
            pattern_regex = child_pattern_to_regex(child_pattern, card_name)
            children_names.any? { |name| name.match?(pattern_regex) }
          end

          if missing_suggested.any?
            warnings << "Consider adding suggested child cards: #{missing_suggested.join(', ')}"
          end
        end

        {
          valid: errors.empty?,
          errors: errors,
          warnings: warnings,
          required_children: required_children,
          suggested_children: suggested_children,
          has_children: has_children
        }
      end

      def get_type_requirements(card_type)
        # Get available tags from wiki
        available_tags = fetch_available_tags

        # Define requirements for common card types using actual wiki tags
        requirements = {
          "Article" => {
            required_tags: [],
            suggested_tags: filter_existing_tags(["Status", "Category", "Draft", "Published"], available_tags),
            required_children: [],
            suggested_children: ["*content", "*summary"]
          },
          "Game Master Document" => {
            required_tags: filter_existing_tags(["GM"], available_tags),
            suggested_tags: filter_existing_tags(["Game", "System", "Butterfly Galaxii", "Spoiler"], available_tags),
            required_children: [],
            suggested_children: []
          },
          "Player Document" => {
            required_tags: [],
            suggested_tags: filter_existing_tags(["Game", "System", "Player", "Butterfly Galaxii"], available_tags),
            required_children: [],
            suggested_children: []
          },
          "Species" => {
            required_tags: [],
            suggested_tags: filter_existing_tags(["Game", "Species", "Butterfly Galaxii", "Alien"], available_tags),
            required_children: [],
            suggested_children: ["*traits", "*description", "*culture"]
          },
          "Faction" => {
            required_tags: [],
            suggested_tags: filter_existing_tags(["Game", "Faction", "Butterfly Galaxii", "Organization"], available_tags),
            required_children: [],
            suggested_children: ["*description", "*goals", "*leadership"]
          },
          "Character" => {
            required_tags: [],
            suggested_tags: filter_existing_tags(["Game", "Character", "Player", "NPC"], available_tags),
            required_children: [],
            suggested_children: ["*background", "*stats", "*inventory"]
          },
          "Location" => {
            required_tags: [],
            suggested_tags: filter_existing_tags(["Game", "Location", "Planet", "System"], available_tags),
            required_children: [],
            suggested_children: ["*description", "*geography", "*notable_features"]
          },
          "Technology" => {
            required_tags: [],
            suggested_tags: filter_existing_tags(["Game", "Technology", "Tech", "Equipment"], available_tags),
            required_children: [],
            suggested_children: ["*description", "*capabilities", "*limitations"]
          }
        }

        # Return requirements or defaults
        requirements[card_type] || {
          required_tags: [],
          suggested_tags: [],
          required_children: [],
          suggested_children: []
        }
      end

      def fetch_available_tags
        # Cache available tags for 5 minutes to avoid repeated queries
        @available_tags ||= begin
          cache_key = "mcp_available_tags"
          cached = Rails.cache.read(cache_key)

          if cached
            cached
          else
            tags = fetch_tags_from_wiki
            Rails.cache.write(cache_key, tags, expires_in: 5.minutes)
            tags
          end
        end
      end

      def fetch_tags_from_wiki
        # Try to fetch all Tag type cards with proper auth context
        tag_cards = Card::Auth.as(current_account.name) do
          Card.search(type: "Tag", limit: 500)
        end
        tag_names = tag_cards.map(&:name).compact

        # If no Tag type exists, try searching for cards ending with +tags
        if tag_names.empty?
          tags_subcards = Card::Auth.as(current_account.name) do
            Card.search(name: ["match", "*+tags"], limit: 500)
          end
          # Extract unique tag values from content
          tag_names = tags_subcards.flat_map do |card|
            extract_tags_from_content(card.content || "")
          end.uniq
        end

        tag_names.sort
      rescue StandardError => e
        # Fallback to common tags if wiki fetch fails
        Rails.logger.warn("Failed to fetch tags from wiki: #{e.message}")
        ["GM", "Game", "Player", "Species", "Faction", "Character", "Draft", "Published"]
      end

      def filter_existing_tags(desired_tags, available_tags)
        # Return only tags that actually exist in the wiki
        desired_tags.select { |tag| available_tags.include?(tag) }
      end

      def extract_tags_from_content(content)
        tags = []
        # Extract [[...]] format
        content.scan(/\[\[([^\]]+)\]\]/) do |match|
          tags << match[0].strip
        end
        # If no bracket tags, try line-separated
        if tags.empty?
          tags = content.split(/[\n,]/).map(&:strip).reject(&:empty?)
        end
        tags
      end

      def suggest_tags_from_content(content, existing_tags)
        suggestions = []

        # Game-related content
        if content.match?(/game master|GM only|spoiler/i) && !existing_tags.include?("GM")
          suggestions << "GM"
        end

        # Species/faction mentions
        if content.match?(/species|race|alien/i) && !existing_tags.include?("Species")
          suggestions << "Species"
        end

        if content.match?(/faction|organization|group/i) && !existing_tags.include?("Faction")
          suggestions << "Faction"
        end

        # Status tags
        if content.match?(/draft|work in progress|WIP/i) && !existing_tags.include?("Draft")
          suggestions << "Draft"
        end

        if content.match?(/complete|finished|published/i) && !existing_tags.include?("Complete")
          suggestions << "Complete"
        end

        suggestions
      end

      def check_naming_conventions(card_name, card_type, tags)
        warnings = []

        # Check for GM content naming
        if card_name.include?("+GM") && !tags.include?("GM")
          warnings << "Card name includes '+GM' but missing 'GM' tag"
        end

        # Check for AI content naming
        if card_name.include?("+AI") && !tags.include?("AI")
          warnings << "Card name includes '+AI' but missing 'AI' tag"
        end

        # Check for player-facing content
        if card_type == "Game Master Document" && !card_name.include?("+GM")
          warnings << "GM documents should typically use '+GM' in the card name"
        end

        warnings
      end

      def generate_structure_recommendations(card_type, card_name, tags, content)
        requirements = get_type_requirements(card_type)

        # Generate child card recommendations
        child_recommendations = []
        (requirements[:suggested_children] || []).each do |child_pattern|
          child_recommendations << {
            name: "#{card_name}+#{child_pattern.gsub('*', '')}",
            type: infer_child_type(child_pattern),
            purpose: describe_child_purpose(child_pattern),
            priority: "suggested"
          }
        end

        (requirements[:required_children] || []).each do |child_pattern|
          child_recommendations << {
            name: "#{card_name}+#{child_pattern.gsub('*', '')}",
            type: infer_child_type(child_pattern),
            purpose: describe_child_purpose(child_pattern),
            priority: "required"
          }
        end

        # Generate tag recommendations
        tag_recommendations = {
          required: requirements[:required_tags] || [],
          suggested: requirements[:suggested_tags] || [],
          content_based: suggest_tags_from_content(content, tags)
        }

        # Generate naming recommendations
        naming_recommendations = generate_naming_recommendations(card_name, card_type, tags)

        {
          card_type: card_type,
          card_name: card_name,
          children: child_recommendations,
          tags: tag_recommendations,
          naming: naming_recommendations,
          summary: generate_recommendation_summary(child_recommendations, tag_recommendations)
        }
      end

      def analyze_card_and_suggest_improvements(card)
        card_type = card.type_name
        # Get existing children using left_id (Decko parent-child relationship)
        existing_children = if card.id
                              Card.where(left_id: card.id).map(&:name)
                            else
                              []
                            end
        existing_tags = extract_tags_from_card(card)

        requirements = get_type_requirements(card_type)

        improvements = {
          card_name: card.name,
          card_type: card_type,
          missing_children: [],
          missing_tags: [],
          suggested_additions: [],
          naming_issues: []
        }

        # Check for missing required children
        (requirements[:required_children] || []).each do |child_pattern|
          pattern_regex = child_pattern_to_regex(child_pattern, card.name)
          unless existing_children.any? { |name| name.match?(pattern_regex) }
            improvements[:missing_children] << {
              pattern: child_pattern,
              suggestion: "#{card.name}+#{child_pattern.gsub('*', '')}",
              priority: "required"
            }
          end
        end

        # Check for missing suggested children
        (requirements[:suggested_children] || []).each do |child_pattern|
          pattern_regex = child_pattern_to_regex(child_pattern, card.name)
          unless existing_children.any? { |name| name.match?(pattern_regex) }
            improvements[:suggested_additions] << {
              pattern: child_pattern,
              suggestion: "#{card.name}+#{child_pattern.gsub('*', '')}",
              priority: "suggested"
            }
          end
        end

        # Check for missing tags
        required_tags = requirements[:required_tags] || []
        missing_required = required_tags - existing_tags
        improvements[:missing_tags] = missing_required

        # Check naming conventions
        improvements[:naming_issues] = check_naming_conventions(card.name, card_type, existing_tags)

        # Add improvement summary
        improvements[:summary] = generate_improvement_summary(improvements)

        improvements
      end

      def infer_child_type(child_pattern)
        # Infer child card type based on pattern
        case child_pattern
        when /content|description|summary/i
          "RichText"
        when /tags|categories/i
          "Pointer"
        when /stats|attributes/i
          "Number"
        when /list|items/i
          "Pointer"
        else
          "Basic"
        end
      end

      def describe_child_purpose(child_pattern)
        # Describe the purpose of a child card based on pattern
        clean_pattern = child_pattern.gsub("*", "")

        descriptions = {
          "content" => "Main content section",
          "summary" => "Brief overview or summary",
          "description" => "Detailed description",
          "traits" => "Characteristics and traits",
          "culture" => "Cultural information",
          "goals" => "Objectives and goals",
          "leadership" => "Leadership structure",
          "background" => "Background information",
          "stats" => "Statistics and attributes",
          "inventory" => "Items and possessions"
        }

        descriptions[clean_pattern.downcase] || "Additional information: #{clean_pattern}"
      end

      def generate_naming_recommendations(card_name, card_type, tags)
        recommendations = []

        # GM content recommendations
        if card_type == "Game Master Document" && !card_name.include?("+GM")
          recommendations << {
            issue: "GM documents should use '+GM' suffix",
            suggestion: "#{card_name}+GM",
            reason: "Separates GM-only content from player-facing content"
          }
        end

        # Tag-based naming
        if tags.include?("GM") && !card_name.include?("+GM") && !card_name.include?("+AI")
          recommendations << {
            issue: "Tagged as GM but name doesn't reflect this",
            suggestion: "#{card_name}+GM",
            reason: "Makes GM content easily identifiable"
          }
        end

        recommendations
      end

      def generate_recommendation_summary(child_recommendations, tag_recommendations)
        required_children = child_recommendations.count { |c| c[:priority] == "required" }
        suggested_children = child_recommendations.count { |c| c[:priority] == "suggested" }

        parts = []
        parts << "#{required_children} required children" if required_children > 0
        parts << "#{suggested_children} suggested children" if suggested_children > 0
        parts << "#{tag_recommendations[:required].length} required tags" if tag_recommendations[:required].any?
        parts << "#{tag_recommendations[:suggested].length} suggested tags" if tag_recommendations[:suggested].any?

        parts.any? ? "Recommendations: #{parts.join(', ')}" : "No additional recommendations"
      end

      def generate_improvement_summary(improvements)
        parts = []
        parts << "#{improvements[:missing_children].length} required children missing" if improvements[:missing_children].any?
        parts << "#{improvements[:suggested_additions].length} suggested additions" if improvements[:suggested_additions].any?
        parts << "#{improvements[:missing_tags].length} required tags missing" if improvements[:missing_tags].any?
        parts << "#{improvements[:naming_issues].length} naming issues" if improvements[:naming_issues].any?

        parts.any? ? parts.join(', ') : "No improvements needed"
      end

      def extract_tags_from_card(card)
        # Try to get tags from +tags subcard
        tags_card = card.fetch(trait: "tags")
        return [] unless tags_card

        content = tags_card.content || ""

        # Extract tags from content
        tags = []
        content.scan(/\[\[([^\]]+)\]\]/) do |match|
          tags << match[0].strip
        end

        tags.empty? ? content.split(/[\n,]/).map(&:strip).reject(&:empty?) : tags
      rescue StandardError
        []
      end

      def child_pattern_to_regex(child_pattern, card_name = nil)
        # Convert pattern like "*background" to regex that matches "CardName+background"
        # The asterisk (*) in patterns is a wildcard for the parent card name
        if child_pattern.start_with?("*")
          # Pattern like "*background" should match any "Something+background"
          suffix = Regexp.escape(child_pattern[1..])
          if card_name
            # If we have card name, match specifically "CardName+suffix"
            Regexp.new("^#{Regexp.escape(card_name)}\\+#{suffix}$")
          else
            # Without card name, match any "...+suffix"
            Regexp.new("\\+#{suffix}$")
          end
        else
          # Pattern doesn't start with *, treat as literal (escape special chars)
          Regexp.new("^#{Regexp.escape(child_pattern)}$")
        end
      end
    end
  end
end
