# frozen_string_literal: true

module Jobs
  class TaperImportFeed < ::Jobs::Base
    sidekiq_options retry: false

    # Resolved at call time, not class load. The importers live in lib/ and
    # are required from after_initialize, so a class-level constant here
    # is evaluated before they exist under eager loading and breaks boot.
    def self.importers
      {
        "archive_org" => DiscourseTaper::Importers::ArchiveOrg,
        "youtube" => DiscourseTaper::Importers::Youtube,
      }
    end

    def execute(args)
      band = DiscourseTaper::Band.find_by(id: args[:band_id])
      importer = self.class.importers[args[:importer].to_s]
      return if band.nil? || importer.nil? || !importer.available?

      stats = importer.new(band: band).run
      Rails.logger.info(
        "#{DiscourseTaper::PLUGIN_NAME}: #{importer.key} for #{band.slug}: #{stats}",
      )
    rescue DiscourseTaper::Error,
           JSON::ParserError,
           SocketError,
           Timeout::Error,
           Net::OpenTimeout,
           Net::ReadTimeout,
           FinalDestination::SSRFDetector::DisallowedIpError => e
      Rails.logger.warn(
        "#{DiscourseTaper::PLUGIN_NAME}: #{args[:importer]} for band #{args[:band_id]} failed: #{e.class}: #{e.message}",
      )
    end
  end
end
