# frozen_string_literal: true

module Jobs
  class TaperImportFeed < ::Jobs::Base
    sidekiq_options retry: false

    IMPORTERS = {
      "archive_org" => DiscourseTaper::Importers::ArchiveOrg,
      "youtube" => DiscourseTaper::Importers::Youtube,
    }.freeze

    def execute(args)
      band = DiscourseTaper::Band.find_by(id: args[:band_id])
      importer = IMPORTERS[args[:importer].to_s]
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
