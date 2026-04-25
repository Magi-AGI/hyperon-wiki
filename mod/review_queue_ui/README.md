# review_queue_ui

Presentation tweaks for the **Review Queue** search card (codename
`review_queue`, defined in `mod/editorial_review/data/real.yml`).

Lives in its own mod so editor-facing UX changes don't tangle with the
workflow rules in `mod/editorial_review/`.

## Current behavior

* **Open in new tab on click.** Left-clicking a row in the Review Queue
  opens that card in a new browser tab instead of slot-loading it in
  place. Lets reviewers preload several cards at once for offline work
  (e.g., on a flight). Implemented in
  `assets/script/open_in_new_tab.js.coffee`.

  Modifier keys (Ctrl/Cmd/Shift/Alt, middle-click) keep their normal
  browser meanings. Clicks on dropdown-menu items inside a row (page,
  modal, edit, advanced) are left alone and behave as before.
