# frozen_string_literal: true

# Placeholder for future Ruby-side overrides of the Review Queue card
# (codename :review_queue, declared in mod/editorial_review/data/real.yml).
#
# Today's "open in new tab" behavior is implemented entirely in
# assets/script/open_in_new_tab.js.coffee — the bar wrapper produced by
# card-mod-bar_and_box hijacks clicks via JS (event.preventDefault then
# window.location = ...), so a server-side target="_blank" on an inner
# anchor would be neutralized. JS in the capture phase is the reliable
# place to override that.
#
# Add Ruby view overrides here when we need them (e.g., custom column
# layout, inline status badges, bulk-action checkboxes).
