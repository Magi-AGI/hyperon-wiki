# Client-side right sidebar: breadcrumbs + table of contents.
#
# Runs after each Decko slot render (including slotter updates) so the TOC
# stays in sync when the main content changes via ajax navigation.
#
# Breadcrumbs are derived from the page title / card name in the article.
# TOC is built by scanning <article> for h2, h3, h4 headings.

buildPageSidebar = ->
  sidebar = document.getElementById("sidebar-right")
  article = document.querySelector("article")
  return unless sidebar && article

  sidebar.innerHTML = ""
  sidebar.appendChild(buildBreadcrumbs(article))
  toc = buildToc(article)
  sidebar.appendChild(toc) if toc

# ── Breadcrumbs ──────────────────────────────────────────────────────────────

buildBreadcrumbs = (article) ->
  frag = document.createDocumentFragment()

  # Derive card name from the h1 title inside the article, or from the URL.
  h1 = article.querySelector("h1.d0-card-header-title .card-title")
  rawName = if h1 then h1.getAttribute("title") else decodeURIComponent(location.pathname.slice(1))
  return frag if !rawName || rawName.indexOf("+") < 0

  parts = rawName.split("+")
  nav = document.createElement("nav")
  nav.setAttribute("aria-label", "breadcrumb")
  nav.className = "wiki-breadcrumbs mb-2"

  ol = document.createElement("ol")
  ol.className = "breadcrumb small"

  parts.forEach (part, i) ->
    li = document.createElement("li")
    if i == parts.length - 1
      li.className = "breadcrumb-item active"
      li.setAttribute("aria-current", "page")
      li.textContent = part.replace(/_/g, " ")
    else
      li.className = "breadcrumb-item"
      ancestor = parts.slice(0, i + 1).join("+")
      a = document.createElement("a")
      a.href = "/" + ancestor
      a.textContent = part.replace(/_/g, " ")
      li.appendChild(a)
    ol.appendChild(li)

  nav.appendChild(ol)
  frag.appendChild(nav)
  frag

# ── Table of Contents ────────────────────────────────────────────────────────

buildToc = (article) ->
  headings = Array.from(article.querySelectorAll("h2, h3, h4"))
  return null if headings.length == 0

  # Stamp id attributes on headings that lack them so anchor links work.
  headings.forEach (h) ->
    unless h.id
      h.id = h.textContent.trim().toLowerCase()
                .replace(/[^a-z0-9\-]+/g, "-")
                .replace(/^-+|-+$/, "")

  nav = document.createElement("nav")
  nav.className = "wiki-toc mb-3"
  nav.setAttribute("aria-label", "Page contents")

  heading = document.createElement("p")
  heading.className = "wiki-toc-heading text-muted small text-uppercase mb-1 fw-semibold"
  heading.textContent = "Contents"
  nav.appendChild(heading)

  ul = document.createElement("ul")
  ul.className = "list-unstyled"

  headings.forEach (h) ->
    level = parseInt(h.tagName[1], 10) - 1  # h2→1, h3→2, h4→3
    li = document.createElement("li")
    li.className = "toc-#{h.tagName.toLowerCase()} ps-#{level * 2}"
    a = document.createElement("a")
    a.href = "#" + h.id
    a.textContent = h.textContent.trim()
    li.appendChild(a)
    ul.appendChild(li)

  nav.appendChild(ul)
  nav

# ── Event wiring ─────────────────────────────────────────────────────────────

# Run on initial load and after every Decko slot update.
$(document).on "ready slotReady", -> buildPageSidebar()
