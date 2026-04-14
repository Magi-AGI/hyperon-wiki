# Append TinyMCE fullscreen plugin + toolbar control to whatever *tinyMCE JSON provides.
# Runs after card-mod-tinymce_editor defines decko.initTinyMCE (local mods load after gem mods).
do ->
  orig = decko.initTinyMCE
  decko.initTinyMCE = (el_id) ->
    cfg = decko.tinyMCEConfig ?= {}

    plugins = cfg.plugins
    if plugins
      unless /\bfullscreen\b/.test plugins
        cfg.plugins = "#{plugins} fullscreen".replace(/\s+/g, " ").trim()
    else
      cfg.plugins = "autoresize fullscreen"

    for key in ["toolbar1", "toolbar", "toolbar2", "toolbar3"]
      if cfg[key]
        val = cfg[key]
        unless val.indexOf("fullscreen") >= 0
          cfg[key] = "#{val} | fullscreen"

    orig.call decko, el_id
