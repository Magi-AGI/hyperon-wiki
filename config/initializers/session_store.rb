# Session store configuration for Cloudflare compatibility
Rails.application.config.session_store :cookie_store,
  key: '_hyperon_session',
  same_site: :lax,
  secure: false,  # Changed to false because Cloudflare Flexible SSL sends HTTP to server
  httponly: true,
  expire_after: 2.hours

# Ensure cookies work with Cloudflare proxy
Rails.application.config.action_dispatch.cookies_same_site_protection = :lax
