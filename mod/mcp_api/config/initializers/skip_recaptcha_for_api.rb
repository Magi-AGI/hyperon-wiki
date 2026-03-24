# frozen_string_literal: true

# Bypass reCAPTCHA for authenticated MCP API requests
# Web forms still require reCAPTCHA validation
Card.class_eval do
  def validate_recaptcha?
    # Skip reCAPTCHA if request is from MCP API controller
    controller = Card::Env.controller
    if controller && controller.class.name.to_s.start_with?('Api::Mcp::')
      Rails.logger.info "MCP API: Skipping reCAPTCHA for #{controller.class.name}"
      return false
    end
    
    # Original Decko reCAPTCHA validation logic
    return false unless Card::Codename.exist? :captcha
    
    !@supercard && !:captcha.card.captcha_used? && recaptcha_on?
  end
end
