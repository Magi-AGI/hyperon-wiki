# Ensure new cards correctly inherit permissions from restricted parents
#
# When a new card is created under a parent that has restricted permissions
# (via +*self+*read or similar), this hook ensures the new card's read_rule_id
# is correctly set by explicitly triggering permission repair.
#
# This prevents the race condition where a card might be created before
# Decko's normal permission inheritance logic fully processes.

event :ensure_inherited_permissions, :finalize, on: :create do
  ensure_correct_permission_inheritance
end

def ensure_correct_permission_inheritance
  # Only process compound cards (those with a parent)
  return unless compound?

  # Check if any ancestor has a restricted +*self+*read rule
  # by checking if they point to something other than *all+*read
  parent_card = left
  return unless parent_card

  # Get the parent's read rule
  parent_rule_id = parent_card.read_rule_id
  all_read_rule_id = Card.fetch("*all+*read")&.id

  # If parent has a non-default read rule, ensure we inherit correctly
  if parent_rule_id && parent_rule_id != all_read_rule_id
    # The parent has restricted permissions - make sure we inherit them
    Card::Auth.as_bot do
      include_set_modules
      repair_permissions!
    end

    Rails.logger.debug "[PermissionPropagation] New card #{name} inherits permissions from #{parent_card.name}"
  end
end
