# Automatically propagate permission changes to descendant cards
#
# When a +*read rule is created or updated, this hook repairs the
# read_rule_id cache on all descendant cards that inherit from the
# affected parent via the _left pattern.
#
# This fixes the issue where child cards retain stale permission
# caches pointing to *all+*read instead of inheriting from their
# restricted parent.

# Only apply to *read cards (permission rules)
def self.applies_to_cardname? name
  name.tag_name&.key == "*read"
end

event :propagate_read_permission_to_descendants, :finalize,
      on: :save, when: :permission_rule_changed? do
  propagate_permissions_to_descendants
end

def permission_rule_changed?
  # Trigger on create or when content changes
  return true if action == :create
  return true if db_content_changed?
  false
end

def propagate_permissions_to_descendants
  # Get the card this permission rule applies to
  # For "Parent+*self+*read", the target is "Parent"
  # For "Parent+*right+*read", all cards with +Parent as right part
  target_card = permission_target_card
  return unless target_card

  Rails.logger.info "[PermissionPropagation] +*read rule saved for: #{target_card.name}"

  # Repair permissions on target and all its descendants
  Card::Auth.as_bot do
    repair_descendant_permissions(target_card)
  end
end

def permission_target_card
  # The card this rule applies to is the trunk's trunk
  # e.g., "Games+GM Docs+*self+*read" -> trunk is "Games+GM Docs+*self" -> trunk is "Games+GM Docs"
  return nil unless name.parts.length >= 3

  # Handle different rule patterns
  rule_type = name.parts[-2] # *self, *right, *type, etc.

  case rule_type
  when "*self"
    # Direct card rule: "CardName+*self+*read"
    target_name = name.trunk_name.trunk_name
    Card.fetch(target_name)
  when "*right"
    # Right-side rule: affects all cards with this as right part
    # We'll handle this differently - repair all cards with matching right part
    nil # TODO: Could expand to handle *right patterns
  else
    # For other patterns, try the trunk's trunk
    target_name = name.trunk_name.trunk_name
    Card.fetch(target_name)
  end
end

def repair_descendant_permissions(parent_card)
  return unless parent_card

  repaired_count = 0

  # First repair the parent itself
  old_rule_id = parent_card.read_rule_id
  parent_card.include_set_modules
  parent_card.repair_permissions!

  if old_rule_id != parent_card.read_rule_id
    repaired_count += 1
    Rails.logger.info "[PermissionPropagation] Repaired parent: #{parent_card.name}"
  end

  # Get all descendants using field_cards recursively
  descendants = collect_all_descendants(parent_card)

  descendants.each do |descendant|
    next if descendant.name.include?("+*") # Skip rule cards themselves

    old_rule_id = descendant.read_rule_id
    descendant.include_set_modules
    descendant.repair_permissions!

    if old_rule_id != descendant.read_rule_id
      repaired_count += 1
    end
  end

  Rails.logger.info "[PermissionPropagation] Repaired #{repaired_count} cards under #{parent_card.name}"
end

def collect_all_descendants(card, results = [])
  card.field_cards.each do |field|
    results << field
    collect_all_descendants(field, results)
  end
  results
end
