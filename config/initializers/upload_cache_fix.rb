# frozen_string_literal: true

# Fix for Decko 0.19.1 file upload bug
#
# ISSUE: Web-based file uploads fail with "Validation failed: File is missing"
#        even though the file is successfully cached in tmp/295/<action_id>.pdf
#
# ROOT CAUSE: The assign_attachment_on_create event doesn't properly retrieve
#             cached files during Stage 2 of Decko's two-stage upload process.
#             CarrierWave's attachment.file remains nil after select_file_revision.
#
# SOLUTION: Override assign_attachment_on_create using prepend to add a disk
#           fallback when CarrierWave fails to hydrate the uploader.
#
# IMPACT ON UPDATES:
# - This fix uses Ruby's prepend to take precedence in method lookup
# - SAFE: If Decko fixes the bug, this fallback will still work (but be unused)
# - REQUIRES TESTING: After any Decko update, test file uploads to ensure compatibility
# - CAN BE REMOVED: Once Decko fixes this upstream, delete this file and restart
#
# TO TEST AFTER UPDATES:
# 1. Upload a PDF through web interface at https://wiki.magi-agi.org
# 2. Check logs: tail -f /home/ubuntu/magi-archive/log/production.log | grep UploadCacheFix
# 3. Should see: "UploadCacheFix: assigning cached file" followed by "Completed 200 OK"
#
# DECKO VERSION: 0.19.1 (2025-10-26)
# REPORTED: https://github.com/decko-commons/decko/issues/... (TODO: file issue)

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

    # For images, CarrierWave creates multiple versions (original, medium, etc.)
    # For files, it just stores the original
    ext = File.extname(action.comment.to_s)

    candidates = [
      File.join(base_dir, "#{action.id}.pdf"),
      File.join(base_dir, "#{action.id}#{ext}"),
      File.join(base_dir, "#{action.id}-original#{ext}"),  # Images use -original suffix
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

  if defined?(Card::Set::Type::Image)
    Card::Set::Type::Image.prepend(UploadCacheFix)
    Rails.logger.info "=== UploadCacheFix module prepended to Card::Set::Type::Image"
  end
end
