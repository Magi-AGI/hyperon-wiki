# frozen_string_literal: true

# Overrides label text for sign-in/out/up links and the account dropdown.
# card-mod-layout's account_link_text falls back to i18n ("account_sign_in" etc);
# we intercept it here so the navbar shows our preferred labels.
# account_dropdown_label controls the clickable account name shown when signed in.

format :html do
  def account_link_text(purpose)
    labels = { sign_in: "Login 🔑", sign_out: "Logout ⏻", sign_up: "Register" }
    labels.fetch(purpose) { super }
  end

  def account_dropdown_label
    link_to_mycard("Account 👤")
  end
end
