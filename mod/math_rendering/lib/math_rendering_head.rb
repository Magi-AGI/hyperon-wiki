# frozen_string_literal: true

# MathRenderingHead
# Injects KaTeX CSS and JavaScript into the page <head> for client-side
# math rendering. Supports \(...\) for inline math and \[...\] for
# display math. Re-renders after Decko AJAX slot loads via decko.slot.ready.

module MathRenderingHead
  private

  def head_content
    super + katex_head_tags
  end

  def katex_head_tags
    <<~'HTML'
      <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.css" crossorigin="anonymous">
      <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/katex.min.js" crossorigin="anonymous"></script>
      <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.22/dist/contrib/auto-render.min.js" crossorigin="anonymous"></script>
      <script>
      document.addEventListener("DOMContentLoaded", function() {
        var mathOpts = {
          delimiters: [
            {left: "\\[", right: "\\]", display: true},
            {left: "\\(", right: "\\)", display: false}
          ],
          throwOnError: false
        };
        if (window.renderMathInElement) {
          renderMathInElement(document.body, mathOpts);
        }
        if (typeof decko !== "undefined" && decko.slot) {
          decko.slot.ready(function(slot) {
            if (window.renderMathInElement) {
              renderMathInElement(slot[0], mathOpts);
            }
          });
        }
      });
      </script>
    HTML
  end
end
