# frozen_string_literal: true

require "fileutils"

module Api
  module Mcp
    module Admin
      # Admin controller for database backup operations
      # Requires admin authentication
      class DatabaseController < BaseController
        before_action :require_admin_role

        # GET /api/mcp/admin/database/backup
        # Download a database backup
        def backup
          backup_dir = Rails.root.join("tmp", "backups")
          FileUtils.mkdir_p(backup_dir)

          timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
          backup_filename = "magi_archive_backup_#{timestamp}.sql"
          backup_path = backup_dir.join(backup_filename)

          # Perform database backup
          perform_backup(backup_path)

          # Send file to client
          send_file backup_path,
                    filename: backup_filename,
                    type: "application/sql",
                    disposition: "attachment"

          # Clean up old backups (keep last 5)
          cleanup_old_backups(backup_dir)
        rescue StandardError => e
          render json: {
            error: "backup_failed",
            message: "Database backup failed: #{e.message}",
            details: { error_class: e.class.name }
          }, status: :internal_server_error
        end

        # GET /api/mcp/admin/database/backup/list
        # List available backup files
        def list_backups
          backup_dir = Rails.root.join("tmp", "backups")

          unless Dir.exist?(backup_dir)
            return render json: { backups: [], total: 0 }
          end

          backups = Dir.glob(backup_dir.join("*.sql")).map do |path|
            file = File.new(path)
            {
              filename: File.basename(path),
              size: File.size(path),
              size_human: format_file_size(File.size(path)),
              created_at: File.ctime(path).iso8601,
              modified_at: File.mtime(path).iso8601,
              age: time_ago_in_words(File.mtime(path))
            }
          end.sort_by { |b| b[:modified_at] }.reverse

          render json: {
            backups: backups,
            total: backups.size,
            backup_dir: backup_dir.to_s
          }
        end

        # GET /api/mcp/admin/database/backup/download/:filename
        # Download a specific backup file
        def download_backup
          backup_dir = Rails.root.join("tmp", "backups")
          filename = params[:filename]

          # Security: ensure filename doesn't contain path traversal
          unless filename.match?(/\A[a-zA-Z0-9_\-]+\.sql\z/)
            return render json: {
              error: "invalid_filename",
              message: "Invalid backup filename"
            }, status: :bad_request
          end

          backup_path = backup_dir.join(filename)

          unless File.exist?(backup_path)
            return render json: {
              error: "not_found",
              message: "Backup file not found"
            }, status: :not_found
          end

          send_file backup_path,
                    filename: filename,
                    type: "application/sql",
                    disposition: "attachment"
        end

        # DELETE /api/mcp/admin/database/backup/:filename
        # Delete a specific backup file
        def delete_backup
          backup_dir = Rails.root.join("tmp", "backups")
          filename = params[:filename]

          # Security: ensure filename doesn't contain path traversal
          unless filename.match?(/\A[a-zA-Z0-9_\-]+\.sql\z/)
            return render json: {
              error: "invalid_filename",
              message: "Invalid backup filename"
            }, status: :bad_request
          end

          backup_path = backup_dir.join(filename)

          unless File.exist?(backup_path)
            return render json: {
              error: "not_found",
              message: "Backup file not found"
            }, status: :not_found
          end

          File.delete(backup_path)

          render json: {
            message: "Backup deleted successfully",
            filename: filename
          }
        end

        private

        def perform_backup(backup_path)
          # Get database configuration
          config = ActiveRecord::Base.connection_db_config.configuration_hash

          case config[:adapter]
          when "postgresql", "postgis"
            perform_postgres_backup(config, backup_path)
          when "mysql2"
            perform_mysql_backup(config, backup_path)
          when "sqlite3"
            perform_sqlite_backup(config, backup_path)
          else
            raise "Unsupported database adapter: #{config[:adapter]}"
          end
        end

        def perform_postgres_backup(config, backup_path)
          # Build pg_dump command
          cmd = ["pg_dump"]
          cmd << "-h" << config[:host] if config[:host]
          cmd << "-p" << config[:port].to_s if config[:port]
          cmd << "-U" << config[:username] if config[:username]
          cmd << "--no-password"  # Use .pgpass or environment variable
          cmd << "-F" << "p"  # Plain text format
          cmd << "-f" << backup_path.to_s
          cmd << config[:database]

          # Set password via environment if provided
          env = {}
          env["PGPASSWORD"] = config[:password] if config[:password]

          # Execute backup
          success = system(env, *cmd)
          raise "pg_dump failed" unless success
        end

        def perform_mysql_backup(config, backup_path)
          # Build mysqldump command
          cmd = ["mysqldump"]
          cmd << "-h" << config[:host] if config[:host]
          cmd << "-P" << config[:port].to_s if config[:port]
          cmd << "-u" << config[:username] if config[:username]
          cmd << "-p#{config[:password]}" if config[:password]
          cmd << "--single-transaction"
          cmd << "--routines"
          cmd << "--triggers"
          cmd << config[:database]

          # Execute backup and redirect to file
          success = system(*cmd, out: backup_path.to_s)
          raise "mysqldump failed" unless success
        end

        def perform_sqlite_backup(config, backup_path)
          # For SQLite, just copy the database file
          db_path = config[:database]
          FileUtils.cp(db_path, backup_path)
        end

        def cleanup_old_backups(backup_dir, keep_count = 5)
          backups = Dir.glob(backup_dir.join("*.sql"))
                      .map { |path| [path, File.mtime(path)] }
                      .sort_by { |_, mtime| mtime }
                      .reverse

          # Delete old backups beyond keep_count
          backups[keep_count..-1]&.each do |path, _|
            File.delete(path)
          end
        end

        def require_admin_role
          unless current_role == "admin"
            render_forbidden("This endpoint requires admin role", { required_role: "admin", current_role: current_role })
          end
        end

        def format_file_size(bytes)
          return "0 B" if bytes.zero?

          units = %w[B KB MB GB TB]
          exp = (Math.log(bytes) / Math.log(1024)).to_i
          exp = [exp, units.length - 1].min

          "%.2f %s" % [bytes.to_f / (1024 ** exp), units[exp]]
        end

        def time_ago_in_words(time)
          seconds = Time.current - time

          case seconds
          when 0...60
            "#{seconds.to_i} seconds ago"
          when 60...3600
            "#{(seconds / 60).to_i} minutes ago"
          when 3600...86400
            "#{(seconds / 3600).to_i} hours ago"
          when 86400...604800
            "#{(seconds / 86400).to_i} days ago"
          when 604800...2592000
            "#{(seconds / 604800).to_i} weeks ago"
          else
            "#{(seconds / 2592000).to_i} months ago"
          end
        end
      end
    end
  end
end
