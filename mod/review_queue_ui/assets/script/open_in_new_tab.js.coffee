# Open Review Queue rows in a new tab on left-click.
#
# The Review Queue (search card, codename :review_queue) renders each
# result as a card-mod-bar_and_box "bar". The bar's outer wrapper has
# class _card-link, and bar_and_box.js binds a document-level click
# handler that calls preventDefault() then sets window.location = ...
# That makes the row act like a same-tab link, with no <a> for the
# browser's middle-click / open-in-new-tab affordances to grab.
#
# Reviewers want to preload several cards at once (Anna asked while
# heading to the airport). We attach a *capture-phase* native click
# listener so we run before bar_and_box's bubble-phase handler,
# stopImmediatePropagation it, and window.open() the destination.
#
# Modifier keys (Ctrl/Cmd/Shift/Alt) and non-primary buttons are
# passed through untouched so the browser's own behaviors still work.
# Clicks on the row's dropdown menu (page / modal / edit / advanced)
# are left alone too — those are real <a> tags with their own intent.

REVIEW_QUEUE_SELECTOR = "[data-card-name='Review Queue'] ._card-link"

openReviewQueueRowInNewTab = (event) ->
  return unless event.button is 0
  return if event.metaKey or event.ctrlKey or event.shiftKey or event.altKey

  bar = event.target.closest(REVIEW_QUEUE_SELECTOR)
  return unless bar

  # Let dropdown-menu links and any explicit <a> inside the row do their thing.
  return if event.target.closest(".bar-menu, .dropdown-menu, a, button")

  linkName = bar.getAttribute("data-card-link-name") or
             bar.getAttribute("data-card-name")?.replace(/\s/g, "_")
  return unless linkName

  event.preventDefault()
  event.stopImmediatePropagation()
  window.open "/" + linkName, "_blank", "noopener"

document.addEventListener "click", openReviewQueueRowInNewTab, true
