# frozen_string_literal: true

module DiscourseTaper
  class BandSerializer < ApplicationSerializer
    attributes :id, :name, :slug, :description, :url, :primary, :show_count

    def show_count
      object.respond_to?(:show_count) ? object.show_count : object.shows.count
    end
  end
end
