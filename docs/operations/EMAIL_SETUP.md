# Email Setup for the Hyperon Wiki

> **Verified against production: 2026-09-15.** This guide originated as a generic template
> carried over from a sibling Decko deck. The provider section below has been rewritten
> around what a read-only production evidence check actually confirmed for this deployment
> (see *Verified state* below). Host, key path, deck root, and any operational value that
> is not itself one of the verified facts remain `<placeholder>`. Real values, and SMTP
> credentials, live in the **server-access handoff** (the Administrator card and its
> children), never in this repository. Never commit SMTP credentials.

This guide explains how email works for account creation, password resets, and other
email-based features in the Hyperon Wiki's production deployment, and what to do when it
fails.

## Verified state (2026-09-15)

A read-only remote-console check of `.env.production` and a runner-based card lookup
confirmed the following. No values were read, printed, or recorded beyond what's listed
here — SMTP username and password are present but their values were not inspected and must
never be documented.

- Email delivery is **enabled**: `delivery_method: smtp`, `perform_deliveries: true`.
- **Provider: Gmail**, via `smtp.gmail.com`, port `587`, authentication `plain`.
- `.env.production` defines `MAILER_HOST`, `MAILER_PROTOCOL`, `SMTP_ADDRESS`,
  `SMTP_AUTHENTICATION`, `SMTP_DOMAIN`, `SMTP_ENABLE_STARTTLS`, `SMTP_PASSWORD`,
  `SMTP_PORT`, and `SMTP_USERNAME`.
- SMTP username and password are set. Their values are not reproduced here or anywhere in
  this repository — they live in the server-access handoff.

This is the current state, not a choice to preserve indefinitely. If this deployment ever
needs to change providers, that is a separate operations decision — see *Changing the
provider* below.

## Testing email configuration

Use the verified remote-console procedure from
[`DECKO-DATABASE-ACCESS.md`](DECKO-DATABASE-ACCESS.md) rather than `bundle exec rails
console`, since `script/card` is not executable on this deployment and the runner form is
confirmed to work:

```bash
printf '%s\n' 'puts ActionMailer::Base.smtp_settings.slice(:address, :port, :authentication)' \
  | ssh -T -i <ssh-key> <ssh-user>@<deck-host> \
    'cd <deck-root> && set -a && . .env.production && set +a && \
     export PATH=<rbenv-shims>:$PATH && ruby script/card runner -'
```

`.slice(:address, :port, :authentication)` excludes credentials from the diagnostic output —
do not print the full `smtp_settings` hash, since it can include `user_name` and `password`.

To send a live test email, use `Card::Mailer` from the same runner invocation, substituting
a real recipient at the point of use rather than recording one here.

## Sign-up and verification cards (verified 2026-09-15)

A runner-based card lookup found the following sign-up-related cards on this deployment.
**`acceptance email+*right+*structure` and `account approval email+*right+*structure` were
both looked up and not found** — do not assume either exists, and do not treat the former as
the default verification-email template on this deck.

Cards confirmed present:
- `Sign up` — a Cardtype. `Card.fetch("Sign_ups")` and `Card.fetch("Sign ups")` both resolve
  to it.
- `signup alert email` — an Email template.
- `Signup Success` — a RichText card.
- `*signup` — a RichText card.
- `*account` and `*account links` — both exist.

Because the specific verification-email template card was not found where the previous
version of this document assumed it, treat any claim about *which* card renders the
verification email as unconfirmed until checked directly against this deployment (e.g. via
the runner, or by searching the wiki UI for "email" and "signup" cards).

## Recovering when email is down (administrator path)

**Unverified from this evidence.** The read-only card lookup confirmed that the `Sign up`
cardtype and the `*account` / `*account links` cards exist on this deployment. It did not
confirm that a signup-approval action exists, that it can bypass email verification, or what
it looks like in the UI. Do not treat the steps below as a tested procedure — they are an
inference from card existence, not a confirmed workflow:

1. The `Sign up` cardtype confirmed above is a plausible anchor for a sign-up surface in the
   wiki UI — look for a `Sign_ups` or `Sign ups` listing (both names resolve to the same
   cardtype) among pending accounts, if one exists.
2. `*account` and `*account links` are confirmed to exist, but whether either exposes an
   approval action that bypasses email verification was not checked.

Before relying on this path during an actual outage, an administrator should verify directly
in the wiki UI whether a signup-approval control exists at all, and what it does — this
document does not establish that one does.

## Changing the provider (future decision, not current state)

The current production provider is Gmail via SMTP, confirmed above. If a future decision is
made to switch — for example to a dedicated transactional-email provider such as SendGrid,
Mailgun, or Amazon SES for higher volume — that is a new operations decision requiring its
own credential provisioning and verification pass, not a continuation of this document. Any
such change should update the *Verified state* section above once confirmed, rather than
reintroducing a generic multi-provider options list here.

## Configuring Decko Email Templates

Decko allows customization of email templates through cards. Only `signup alert email` was
confirmed as an Email template on this deployment; edit it in the wiki UI to customize that
message. `Signup Success` and `*signup` were confirmed present but as **RichText** cards, not
Email templates — their role in the email flow, if any, was not verified in this pass, so do
not edit them expecting to change outgoing email content. Password reset email is handled
automatically by Decko's account flow.

### Customizing Email Sender

In the Decko web interface, you can configure:
- **From Address**: Create or edit email configuration cards
- **Reply-To**: Set in email configuration
- **Email Templates**: Use card-based templates with HTML/Markdown

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
   ssh -i <ssh-key-path> <ssh-user>@<deck-host>
   tail -100 <deck-root>/log/production.log
   ```

2. **Verify SMTP credentials** are correct in `.env.production`

3. **Test SMTP connection** manually:
   ```bash
   telnet smtp.gmail.com 587
   # Should connect successfully
   ```

4. **Check spam folder** - first emails often go to spam

### Account Creation Not Working

1. **Verify email is enabled**: confirmed above (`perform_deliveries: true`)
2. **Check Decko permissions**: Ensure "Anyone" has permission to create `Sign up` cards
3. **Review Decko account settings**: Look for `*account`, `*account links`, or `*signup`
   cards — all confirmed present on this deployment (see *Sign-up and verification cards*
   above)

### Authentication Errors

- Gmail (the confirmed provider on this deployment): make sure the account is using an
  **App Password**, not the account's regular password — SMTP username/password values
  themselves are never documented here, only in the server-access handoff.
- If this deployment ever switches provider (see *Changing the provider* above), that
  provider's own authentication conventions apply and are not generic Gmail rules.

## Recovering when email is failing

See *Recovering when email is down (administrator path)* above — that section is itself
unverified beyond the card-existence checks it describes; there is no confirmed
remote-console fallback for account recovery on this deployment.

## Next Steps

1. Customize the `signup alert email` Email template as needed
2. Set up monitoring for email delivery failures
3. Consider setting up SPF/DKIM records for better deliverability

## Resources

- **Decko Email Documentation**: https://decko.org/flexible_email
- **Rails ActionMailer Guide**: https://guides.rubyonrails.org/action_mailer_basics.html
- **Decko Account Management**: https://decko.org/accounts
