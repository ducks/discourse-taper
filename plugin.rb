# frozen_string_literal: true

# name: discourse-taper
# about: A live music archive for tapers. Shows are topics; recordings, videos, and archive.org items attach to them as sources, found by importers or submitted by people and reviewed before they land.
# version: 0.1.0
# authors: Jake Goldsborough
# url: https://github.com/ducks/discourse-taper
# required_version: 2.7.0

enabled_site_setting :taper_enabled

register_asset "stylesheets/taper.scss"
register_svg_icon "record-vinyl"
register_svg_icon "compact-disc"

module ::DiscourseTaper
  PLUGIN_NAME = "discourse-taper"

  def self.root_path
    "#{Discourse.base_path}/taper"
  end

  def self.category
    id = SiteSetting.taper_category_id.to_i
    id.positive? ? Category.find_by(id: id) : nil
  end
end

require_relative "lib/discourse_taper/engine"

after_initialize do
  require_relative "lib/discourse_taper/errors"
  require_relative "app/models/discourse_taper/band"
  require_relative "app/models/discourse_taper/show"
  require_relative "app/models/discourse_taper/source"
  require_relative "app/models/discourse_taper/suggestion"
  require_relative "app/serializers/discourse_taper/band_serializer"
  require_relative "app/serializers/discourse_taper/source_serializer"
  require_relative "app/serializers/discourse_taper/show_serializer"
  require_relative "app/serializers/discourse_taper/suggestion_serializer"
  require_relative "lib/discourse_taper/show_matcher"
  require_relative "lib/discourse_taper/show_creator"
  require_relative "lib/discourse_taper/suggestion_reviewer"
  require_relative "lib/discourse_taper/importers/base"
  require_relative "lib/discourse_taper/importers/archive_org"
  require_relative "lib/discourse_taper/importers/youtube"
  require_relative "app/jobs/scheduled/taper_import_feeds"
  require_relative "app/jobs/regular/taper_import_feed"
  require_relative "app/controllers/discourse_taper/shows_controller"
  require_relative "app/controllers/discourse_taper/suggestions_controller"

  Discourse::Application.routes.append { mount ::DiscourseTaper::Engine, at: "/taper" }

  # A show topic carries its record so the topic page can render the show
  # card (setlist, sources) without a second request.
  add_to_serializer(
    :topic_view,
    :taper_show,
    include_condition: -> { SiteSetting.taper_enabled },
  ) do
    show = DiscourseTaper::Show.includes(:band, sources: :taper).find_by(topic_id: object.topic.id)
    show && DiscourseTaper::ShowSerializer.new(show, root: false, scope: scope).as_json
  end
end
