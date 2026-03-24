# Email Setup for Magi Archive (Decko)

This guide explains how to configure email for account creation, password resets, and other email-based features in your Decko instance.

## Current Status

Email delivery is now **enabled** in `config/application.rb` but requires SMTP credentials to function.

## SMTP Provider Options

Choose one of these providers and get your credentials:

### Option 1: SendGrid (Recommended for Production)
- **Free Tier**: 100 emails/day
- **Sign up**: https://sendgrid.com/pricing/
- **Settings after signup**:
  ```
  SMTP_ADDRESS=smtp.sendgrid.net
  SMTP_PORT=587
  SMTP_DOMAIN=your-domain.com
  SMTP_USERNAME=apikey
  SMTP_PASSWORD=<your-sendgrid-api-key>
  ```

### Option 2: Mailgun
- **Free Tier**: 100 emails/day (first 3 months)
- **Sign up**: https://www.mailgun.com/pricing/
- **Settings after signup**:
  ```
  SMTP_ADDRESS=smtp.mailgun.org
  SMTP_PORT=587
  SMTP_DOMAIN=your-domain.com
  SMTP_USERNAME=<your-mailgun-username>
  SMTP_PASSWORD=<your-mailgun-password>
  ```

### Option 3: Gmail (Simple but Limited)
- **Free Tier**: ~500 emails/day
- **Requires**: Gmail account + App Password (2FA must be enabled)
- **Get App Password**: https://myaccount.google.com/apppasswords
- **Settings**:
  ```
  SMTP_ADDRESS=smtp.gmail.com
  SMTP_PORT=587
  SMTP_DOMAIN=gmail.com
  SMTP_USERNAME=your-email@gmail.com
  SMTP_PASSWORD=<your-16-char-app-password>
  ```

### Option 4: Amazon SES (Production Scale)
- **Free Tier**: 62,000 emails/month (if sent from EC2)
- **Sign up**: https://aws.amazon.com/ses/
- **More complex setup**: Requires verification, may start in sandbox mode

## Configuration Steps

### 1. Add SMTP Credentials to Production Environment

SSH into your production server and edit `.env.production`:

```bash
ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17
cd /home/ubuntu/magi-archive
nano .env.production
```

Add these variables (using credentials from your chosen provider):

```bash
# Email Configuration
MAILER_HOST=magi-archive.up.railway.app
MAILER_PROTOCOL=https
SMTP_ADDRESS=smtp.sendgrid.net
SMTP_PORT=587
SMTP_DOMAIN=magi-archive.up.railway.app
SMTP_USERNAME=apikey
SMTP_PASSWORD=your-sendgrid-api-key-here
SMTP_AUTHENTICATION=plain
```

**Important**: Replace the values above with your actual SMTP credentials!

### 2. Deploy Updated Configuration

Upload the updated `config/application.rb` file to production:

```bash
# From your local machine
scp -i ~/.ssh/magi-archive-key.pem config/application.rb ubuntu@54.219.9.17:/home/ubuntu/magi-archive/config/
```

### 3. Restart the Application

```bash
ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17
cd /home/ubuntu/magi-archive
# If using systemd service:
sudo systemctl restart magi-archive

# If using Railway:
# Push to git and Railway will auto-deploy
```

## Testing Email Configuration

After configuration, test email delivery using Rails console:

```bash
ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17
cd /home/ubuntu/magi-archive
set -a && source .env.production && set +a
PATH="/home/ubuntu/.rbenv/shims:$PATH" bundle exec rails console
```

In the Rails console:

```ruby
# Test email settings
ActionMailer::Base.smtp_settings
# => Should show your SMTP configuration

# Send a test email (replace with your email)
Card::Mailer.mail(
  to: 'your-email@example.com',
  from: 'noreply@magi-archive.up.railway.app',
  subject: 'Test Email',
  body: 'If you receive this, email is working!'
).deliver_now
```

## Configuring Decko Email Templates

Decko allows customization of email templates through cards:

### Default Email Templates

1. **Verification Email**: Sent when users sign up
   - Card: `acceptance email+*right+*structure`
   - View at: https://decko.org/acceptance_email+*right+*structure

2. **Signup Alert Email**: Sent to admins when someone signs up
   - Configure notification settings in Decko admin

3. **Password Reset Email**: Sent when users request password reset
   - Automatically handled by Decko

### Customizing Email Sender

In Decko web interface, you can configure:
- **From Address**: Create or edit email configuration cards
- **Reply-To**: Set in email configuration
- **Email Templates**: Use card-based templates with HTML/Markdown

Visit your Decko admin panel and search for "email" cards to customize.

## reCAPTCHA Setup (Optional)

To prevent spam signups, you may want to add reCAPTCHA:

1. **Get reCAPTCHA keys**: https://www.google.com/recaptcha/admin/create
2. **Add to environment**:
   ```bash
   RECAPTCHA_SITE_KEY=your-site-key
   RECAPTCHA_SECRET_KEY=your-secret-key
   ```
3. **Check Decko documentation** for reCAPTCHA integration (may require additional gems)

## Troubleshooting

### Emails Not Sending

1. **Check logs**:
   ```bash
   ssh -i ~/.ssh/magi-archive-key.pem ubuntu@54.219.9.17
   tail -100 /home/ubuntu/magi-archive/log/production.log
   ```

2. **Verify SMTP credentials** are correct in `.env.production`

3. **Test SMTP connection** manually:
   ```bash
   telnet smtp.sendgrid.net 587
   # Should connect successfully
   ```

4. **Check spam folder** - first emails often go to spam

### Account Creation Not Working

1. **Verify email is enabled**: Check that `config.action_mailer.perform_deliveries = true`
2. **Check Decko permissions**: Ensure "Anyone" has permission to create Sign Up cards
3. **Review Decko account settings**: Look for `*account_links` or `*signup` cards in admin

### Authentication Errors

- Gmail: Make sure you're using an **App Password**, not your regular password
- SendGrid: Username should be literally `apikey`, password is your API key
- Mailgun: Use SMTP credentials from Mailgun dashboard, not API keys

## Alternative: Disable Email Verification (Development Only)

If you just want to test account creation without email verification:

**Warning**: This is insecure for production!

1. Set `config.action_mailer.perform_deliveries = false` in `config/application.rb`
2. Create accounts directly via Rails console:
   ```ruby
   Card.create!(
     name: 'user@example.com',
     type_id: Card.fetch_id(:user),
     content: ''
   )
   ```

## Next Steps

After email is configured:
1. Test account creation flow
2. Customize email templates in Decko
3. Set up monitoring for email delivery failures
4. Consider setting up SPF/DKIM records for better deliverability

## Resources

- **Decko Email Documentation**: https://decko.org/flexible_email
- **Rails ActionMailer Guide**: https://guides.rubyonrails.org/action_mailer_basics.html
- **Decko Account Management**: https://decko.org/accounts
