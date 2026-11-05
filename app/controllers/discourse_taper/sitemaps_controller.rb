# frozen_string_literal: true

module DiscourseTaper
  class SitemapsController < ::ApplicationController
    requires_plugin PLUGIN_NAME
    skip_before_action :preload_json, :check_xhr
    before_action :ensure_public_archive
    PAGE_SIZE = 1000

    def self.available?
      SiteSetting.taper_enabled && SiteSetting.enable_sitemap && !SiteSetting.login_required &&
        SiteSetting.allow_index_in_robots_txt? && DiscourseTaper.category.present? &&
        Guardian.new.can_see_category?(DiscourseTaper.category)
    end

    def index
      maps = []
      {
        "shows" => public_shows.count,
        "recordings" => public_sources.count,
        "bands" => Band.count,
      }.each do |kind, count|
        ((count + PAGE_SIZE - 1) / PAGE_SIZE).times { |n| maps << "#{kind}/#{n + 1}" }
      end
      Band.find_each do |band|
        count = SongIndex.new(band).songs.size
        ((count + PAGE_SIZE - 1) / PAGE_SIZE).times { |n| maps << "songs-#{band.id}/#{n + 1}" }
      end
      xml =
        Nokogiri::XML::Builder.new do |doc|
          doc.sitemapindex(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
            maps.each do |name|
              doc.sitemap do
                doc.loc "#{Discourse.base_url_no_prefix}#{DiscourseTaper.root_path}/sitemaps/#{name}.xml"
              end
            end
          end
        end
      render xml: xml.to_xml
    end

    def page
      raise Discourse::NotFound unless params[:page].to_s.match?(/\A[1-9]\d{0,8}\z/)
      offset = (params[:page].to_i - 1) * PAGE_SIZE
      entries =
        case params[:kind]
        when "shows"
          shows =
            public_shows.includes(:band, :topic).order(:id).limit(PAGE_SIZE).offset(offset).to_a
          source_updates =
            Source.where(show_id: shows.map(&:id)).group(:show_id).maximum(:updated_at)
          shows.map do |s|
            [s.url, [s.updated_at, s.topic.updated_at, source_updates[s.id]].compact.max]
          end
        when "recordings"
          public_sources
            .includes(show: :band)
            .order(:id)
            .limit(PAGE_SIZE)
            .offset(offset)
            .map do |s|
              [
                "#{DiscourseTaper.root_path}/recordings/#{s.id}",
                [s.updated_at, s.show.updated_at].max,
              ]
            end
        when "bands"
          Band
            .order(:id)
            .limit(PAGE_SIZE)
            .offset(offset)
            .flat_map { |b| [[b.url, nil], ["#{b.url}/songs", nil], ["#{b.url}/media", nil]] }
        when /\Asongs-(\d+)\z/
          band = Band.find_by(id: Regexp.last_match(1))
          raise Discourse::NotFound unless band
          SongIndex
            .new(band)
            .songs
            .slice(offset, PAGE_SIZE)
            .to_a
            .map { |s| ["#{band.url}/songs/#{s.slug}", nil] }
        else
          raise Discourse::NotFound
        end
      raise Discourse::NotFound if entries.empty?
      xml =
        Nokogiri::XML::Builder.new do |doc|
          doc.urlset(xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9") do
            entries.each do |path, modified|
              doc.url do
                doc.loc "#{Discourse.base_url_no_prefix}#{path}"
                doc.lastmod modified.iso8601 if modified
              end
            end
          end
        end
      response.headers["Cache-Control"] = "no-cache"
      render xml: xml.to_xml
    end

    private

    def ensure_public_archive
      raise Discourse::NotFound unless self.class.available?
    end

    def public_shows
      Show.readable_by
    end

    def public_sources
      Source.where(show_id: public_shows.select(:id))
    end
  end
end
