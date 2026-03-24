# Override verify_url view for email context to generate absolute URLs
format :email_html do
  view :verify_url, cache: :never, denial: :blank do
    base_url = "https://#{ENV["MAILER_HOST"] || "wiki.hyperon.dev"}"
    relative_path = token_url_path :verify_and_activate, anonymous: true
    
    # Check if path is already absolute
    if relative_path.start_with?("http")
      Rails.logger.info "=== EMAIL_HTML verify_url: path is already absolute ==="
      relative_path
    else
      "#{base_url}#{relative_path}"
    end
  end
  
  def token_url_path trigger, extra_payload={}
    path(action: :update,
         card: { trigger: trigger },
         token: new_token(extra_payload))
  end
end

format :email_text do
  view :verify_url, cache: :never, denial: :blank do
    base_url = "https://#{ENV["MAILER_HOST"] || "wiki.hyperon.dev"}"
    relative_path = token_url_path :verify_and_activate, anonymous: true
    
    # Check if path is already absolute
    if relative_path.start_with?("http")
      Rails.logger.info "=== EMAIL_TEXT verify_url: path is already absolute ==="
      relative_path
    else
      "#{base_url}#{relative_path}"
    end
  end
  
  def token_url_path trigger, extra_payload={}
    path(action: :update,
         card: { trigger: trigger },
         token: new_token(extra_payload))
  end
end
