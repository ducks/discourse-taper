# frozen_string_literal: true

module DiscourseTaper
  class BandSerializer < ApplicationSerializer
    attributes :id,
               :name,
               :slug,
               :description,
               :footer,
               :url,
               :primary,
               :show_count,
               :archive_org_collection,
               :archive_org_query,
               :youtube_channel_id,
               :youtube_search_query,
               :setlistfm_artist_name

    def show_count
      object.respond_to?(:show_count) ? object.show_count : object.shows.count
    end
  end
end
