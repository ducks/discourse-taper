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

  # Staff, or a member of the configured reviewer groups. Checked on the
  # server and exposed on the current user, so the client never inspects
  # group membership itself.
  def self.reviewer?(user)
    return false if user.nil?
    return true if user.staff?
    allowed = SiteSetting.taper_reviewer_groups.to_s.split("|").map(&:to_i).reject(&:zero?)
    allowed.any? && GroupUser.exists?(group_id: allowed, user_id: user.id)
  end
end

require_relative "lib/discourse_taper/engine"

after_initialize do
  require_relative "lib/discourse_taper/errors"
  require_relative "app/models/discourse_taper/band"
  require_relative "app/models/discourse_taper/venue"
  require_relative "app/models/discourse_taper/show"
  require_relative "app/models/discourse_taper/source"
  require_relative "app/models/discourse_taper/suggestion"
  require_relative "app/serializers/discourse_taper/band_serializer"
  require_relative "app/serializers/discourse_taper/source_serializer"
  require_relative "app/serializers/discourse_taper/show_serializer"
  require_relative "app/serializers/discourse_taper/suggestion_serializer"
  require_relative "lib/discourse_taper/venue_resolver"
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
  require_relative "app/controllers/discourse_taper/bands_controller"

  # The reviewer queue is an Ember page. An HTML GET reaches the app shell
  # through check_xhr; prepended so it wins over the engine's /:band route.
  Discourse::Application.routes.prepend do
    get "/taper/review" => "discourse_taper/suggestions#index", :constraints => { format: :html }
  end

  Discourse::Application.routes.append { mount ::DiscourseTaper::Engine, at: "/taper" }

  add_to_serializer(
    :current_user,
    :taper_reviewer,
    include_condition: -> { SiteSetting.taper_enabled },
  ) { DiscourseTaper.reviewer?(object) }

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
