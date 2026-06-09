# frozen_string_literal: true

require "kramdown"
require "kramdown-syntax-coderay"

# T1 fix — store Markdown source verbatim; sanitize the rendered HTML instead.
#
# Decko's default `clean_html?` is true, so `Card::Content.clean!` runs on SAVE
# and strips every "<word...>" span from the Markdown *source*, silently
# destroying content: comparison operators, generics (Vec<T>), grammar (<foo>),
# XML/HTML examples, etc. (an unknown "<tag" eats everything up to the next ">",
# which can be many KB). Markdown is converted to HTML at render time, so the
# correct place to strip unsafe HTML is the generated OUTPUT, not the stored
# source. This is the move hinted at by the core comment
# "TODO: move this html-specific code somewhere more appropriate"
# (mod/core/set/all/content.rb).
def clean_html?
  false
end

format :html do
  view :core do
    safe_process_content do |content|
      html = Kramdown::Document.new(
        content,
        syntax_highlighter: :coderay,
        syntax_highlighter_opts: {
          line_numbers: false,
          default_lang: :ruby
        }
      ).to_html
      # Sanitize the *rendered* HTML (whitelist strip), moved here from the
      # destructive store-time clean!. Kramdown entity-escapes code spans/blocks,
      # so their <...> survive; only unsafe real tags are removed from output.
      Card::Content.clean! html
    end
  end
end
