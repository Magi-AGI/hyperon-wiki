# frozen_string_literal: true

# Overrides Decko's default layout to add a right sidebar, yielding a
# two-sidebar wiki layout: left nav tree | article | right (TOC + actions).
#
# body.wiki-layout is targeted by hyperon_ui.scss for CSS Grid positioning.
# The right sidebar renders view :page_sidebar, composed from breadcrumbs
# and page TOC (defined in page_sidebar.rb).

# The primary wiki layout is the "Left Sidebar Layout" card in the database
# (a LayoutType card), not a code-based layout. The two-sidebar structure and
# body.wiki-layout class are set in that card via the wiki admin UI.
#
# view :page_sidebar is called from the layout card via {{_main|page_sidebar}}.
# It composes the right sidebar from breadcrumbs and page TOC (page_sidebar.rb).

format :html do
  view :page_sidebar, cache: :never do
    [render(:breadcrumbs), render(:page_toc)].reject(&:blank?).join
  end
end
