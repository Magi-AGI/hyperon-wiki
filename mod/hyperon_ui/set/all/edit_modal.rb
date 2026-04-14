# Default card edit / new-in-modal to Decko's "full" modal size (modal-full),
# stretched to the viewport via assets/style/hyperon_ui.scss.
format :html do
  def edit_modal_size
    :full
  end
end
