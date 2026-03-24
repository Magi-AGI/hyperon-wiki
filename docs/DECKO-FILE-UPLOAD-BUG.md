# Decko File Upload Bug - Investigation & Resolution

**Date**: 2025-10-26
**Decko Version**: 0.19.1
**Environment**: Production Decko deck (Ubuntu 22.04), Cloudflare proxy (Flexible SSL)
**Status**: RESOLVED

---

## Problem Description

Browser uploads to File cards returned `Validation failed: File is missing` during the second phase of Decko's two-stage upload (the form submission that references `action_id_of_cached_upload`). Console uploads via `Card.create!` succeeded, confirming storage and permissions were intact.

---

## Investigation Summary

1. **Confirmed two-stage workflow**: Stage 1 stored drafts beneath the cache card (for example `tmp/<cache_card_id>/<action_id>.ext`) and created draft `Card::Action` rows. Stage 2 should have rehydrated the file via `upload_cache_card.select_file_revision`.
2. **Validated inputs**: Cached files existed on disk and `Card::Action.fetch(id)` returned the expected `db_content (~<cache_card_id>/<action_id>.ext)` change record.
3. **Reproduced failure**: Stage 2 parameters always carried `action_id_of_cached_upload`, yet `attachment.file` was `nil` when validation ran, triggering the "File is missing" error.
4. **Root cause**: In Decko 0.19.1 the `assign_attachment_on_create` event does not run inside a `with_selected_action_id` context, so CarrierWave never loads the cached file for new cards when called from the web UI.

---

## Implemented Fix

A Rails initializer now patches Decko's attachment set to select the cached action before validation and, if CarrierWave still returns `nil`, opens the cached file directly using the `db_content` identifier recorded on the draft action.

`config/initializers/upload_cache_fix.rb`
```ruby
# frozen_string_literal: true

module UploadCacheFix
  def assign_attachment_on_create
    action = Card::Action.fetch(@action_id_of_cached_upload)
    return unless action

    Rails.logger.info "UploadCacheFix: handling cached action #{action.id}"

    file_handle = nil

    # Try CarrierWave's normal flow first
    upload_cache_card.with_selected_action_id(action.id) do
      upload_cache_card.select_file_revision
      carrierwave_file = upload_cache_card.attachment.file
      if carrierwave_file&.present?
        Rails.logger.info "UploadCacheFix: CarrierWave retrieved file"
        file_handle = carrierwave_file
      else
        Rails.logger.warn "UploadCacheFix: CarrierWave did not return a file, trying disk fallback"
      end
    end

    # Fallback: open file directly from disk
    file_handle ||= retrieve_cached_upload_from_disk(action)

    if file_handle.present?
      Rails.logger.info "UploadCacheFix: assigning cached file to attachment"
      assign_attachment file_handle, action.comment
    else
      Rails.logger.error "UploadCacheFix: could not retrieve cached file for action #{action.id}"
    end
  end

  private

  def retrieve_cached_upload_from_disk(action)
    base_dir = upload_cache_card.tmp_upload_dir
    db_content = action.card_changes&.detect { |c| c.field.to_s == "db_content" }&.value

    candidates = [
      File.join(base_dir, "#{action.id}.pdf"),
      File.join(base_dir, "#{action.id}#{File.extname(action.comment.to_s)}"),
    ]
    candidates << File.join(base_dir, File.basename(db_content)) if db_content

    path = candidates.compact.uniq.detect { |p| File.exist?(p) }

    unless path
      Rails.logger.error "UploadCacheFix: no file found. Checked: #{candidates.inspect}"
      return nil
    end

    Rails.logger.info "UploadCacheFix: opening file from disk: #{path}"
    File.open(path, "rb")
  rescue StandardError => e
    Rails.logger.error "UploadCacheFix: failed to open file: #{e.class}: #{e.message}"
    nil
  end
end

# Apply the fix after Decko loads
Rails.application.config.after_initialize do
  if defined?(Card::Set::Type::File)
    Card::Set::Type::File.prepend(UploadCacheFix)
    Rails.logger.info "=== UploadCacheFix module prepended to Card::Set::Type::File"
  end
end
```

This patch:
- Selects the cached upload (`with_selected_action_id`) so `select_file_revision` repopulates the uploader before validation.
- Falls back to the on-disk cache if CarrierWave still fails.
- Logs retrieval steps to assist with future upgrades.

---

## Verification

- Uploaded multiple PDFs via the browser after restarting the Decko process.
- Observed new log entries (`UploadCacheFix: hydrated via CarrierWave` or `UploadCacheFix: opening cached file ...` followed by `assigning cached file`).
- Confirmed the card content references the new file revision and the attachment downloads correctly.

---

## Operational Notes

- Keep the initializer in place until Decko ships an upstream fix; remove it after verifying uploads on the upgraded version.
- Monitor production logs for `UploadCacheFix` entries after upgrades or configuration changes.
- No infrastructure details (hostnames, IPs, keys) are recorded in this document for security.

---

## System Information

```
Decko Version: 0.19.1
CarrierWave Version: 3.1.2
Rails Version: 7.2.2.2
Ruby Version: 3.2.3
OS: Ubuntu 22.04.5 LTS
Database: PostgreSQL (managed)
```

---

## References

- Decko GitHub: https://github.com/decko-commons/decko
- Decko Documentation: https://decko.org
- `card-mod-carrierwave` gem: https://rubygems.org/gems/card-mod-carrierwave

