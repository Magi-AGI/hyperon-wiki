# Dark/light theme toggle for Hyperon Wiki.
#
# Reads/writes localStorage key "hyperon-theme" ("dark" | "light").
# Applies data-bs-theme attribute on <html> which Bootstrap 5 uses for
# colour-scheme switching. The toggle button (#theme-toggle) is injected
# into the navbar by *header card content.
#
# Runs on every page load — must be idempotent.

do ->
  STORAGE_KEY = "hyperon-theme"
  DARK_ICON   = "🌙"
  LIGHT_ICON  = "☀️"

  applyTheme = (theme) ->
    document.documentElement.setAttribute "data-bs-theme", theme
    btn = document.getElementById "theme-toggle"
    return unless btn
    btn.textContent = if theme is "dark" then LIGHT_ICON else DARK_ICON
    btn.title       = if theme is "dark" then "Switch to light mode" else "Switch to dark mode"

  savedTheme = ->
    try localStorage.getItem STORAGE_KEY
    catch then null

  prefersDark = ->
    window.matchMedia?("(prefers-color-scheme: dark)").matches

  currentTheme = savedTheme() or (if prefersDark() then "dark" else "light")
  applyTheme currentTheme

  document.addEventListener "DOMContentLoaded", ->
    applyTheme currentTheme  # re-apply after DOM ready in case html attr was reset

    btn = document.getElementById "theme-toggle"
    return unless btn

    btn.addEventListener "click", ->
      next = if document.documentElement.getAttribute("data-bs-theme") is "dark"
        "light"
      else
        "dark"
      try localStorage.setItem STORAGE_KEY, next
      applyTheme next
