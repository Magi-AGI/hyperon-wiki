# Client-side sidebar builder: left breadcrumb + right TOC.
#
# Left sidebar (#sidebar-breadcrumb): shows hierarchy path for compound-named
# pages (e.g. "Hyperon > Architecture > Atomspace"). Empty for top-level pages.
#
# Right sidebar (#sidebar-right): full breadcrumb nav + table of contents
# built from h2/h3/h4 headings in the article.
#
# Runs on initial load and after every Decko slot render.

buildPageSidebar = ->
  article = document.querySelector("article")
  return unless article

  # ── Left sidebar breadcrumb (above nav tree) ─────────────────────────────
  leftCrumb = document.getElementById("sidebar-breadcrumb")
  if leftCrumb
    crumbFrag = buildBreadcrumbs(article, compact: true)
    leftCrumb.innerHTML = ""
    leftCrumb.appendChild(crumbFrag)

  # ── Right sidebar: breadcrumb + TOC ──────────────────────────────────────
  right = document.getElementById("sidebar-right")
  if right
    right.innerHTML = ""
    right.appendChild(buildBreadcrumbs(article))
    toc = buildToc(article)
    right.appendChild(toc) if toc

# ── Breadcrumbs ──────────────────────────────────────────────────────────────
#
# opts.compact: omit the final (current) crumb — used in the left sidebar
# where it would duplicate the highlighted nav item.

buildBreadcrumbs = (article, opts = {}) ->
  frag = document.createDocumentFragment()

  h1 = article.querySelector("h1.d0-card-header-title .card-title")
  rawName = if h1 then h1.getAttribute("title") else decodeURIComponent(location.pathname.slice(1))
  return frag if !rawName || rawName.indexOf("+") < 0

  parts = rawName.split("+")
  # In compact mode (left sidebar) skip if there's nothing to show (only one ancestor)
  return frag if opts.compact and parts.length <= 1

  nav = document.createElement("nav")
  nav.setAttribute("aria-label", "breadcrumb")
  nav.className = "wiki-breadcrumbs mb-2"

  ol = document.createElement("ol")
  ol.className = "breadcrumb small mb-0"

  # In compact mode, only show the ancestor chain (not the current leaf)
  display = if opts.compact then parts.slice(0, -1) else parts

  display.forEach (part, i) ->
    li = document.createElement("li")
    isLast = (i == display.length - 1)

    if isLast and not opts.compact
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
    level = parseInt(h.tagName[1], 10) - 1
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

$ -> buildPageSidebar()
$(document).on "slotReady", -> buildPageSidebar()
