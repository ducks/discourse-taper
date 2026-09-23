# frozen_string_literal: true

module Jobs
  # Fans out one job per band per available importer. The per-band job
  # does the network work so a slow service cannot stall the scheduler.
  class TaperImportFeeds < ::Jobs::Scheduled
    every 1.hour

    def execute(_args)
      return if !SiteSetting.taper_enabled

      interval = SiteSetting.taper_import_interval_hours.hours
      last = Discourse.redis.get("taper:last_import_at")
      return if last && Time.zone.parse(last) > interval.ago

      Discourse.redis.set("taper:last_import_at", Time.zone.now.iso8601)

      DiscourseTaper::Band.find_each do |band|
        importers = [
          DiscourseTaper::Importers::SetlistFm,
          DiscourseTaper::Importers::ArchiveOrg,
          DiscourseTaper::Importers::Youtube,
        ]
        importers.each do |importer|
          next if !importer.available?
          Jobs.enqueue(:taper_import_feed, band_id: band.id, importer: importer.key)
        end
      end
    end
  end
end
