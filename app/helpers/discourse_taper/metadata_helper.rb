# frozen_string_literal: true

module DiscourseTaper
  module MetadataHelper
    def reader_title
      [@page_title, @primary_band&.name || SiteSetting.title].compact.join(" - ")
    end

    def reader_description
      return @page_description if @page_description.present?
      if @source
        return(
          I18n.t(
            "taper.seo.recording",
            band: @band.name,
            date: @show.date.iso8601,
            venue: @show.location,
            title: @source.title.presence || @show.title,
          )
        )
      end
      if @listing_title
        return I18n.t("taper.seo.listing", band: @band.name, listing: @listing_title)
      end
      I18n.t(
        "taper.seo.#{action_name == "media" ? "media" : action_name == "songs" ? "songs" : "band"}",
        band: @band.name,
      )
    end

    def reader_alternates
      locale_links.map do |link|
        uri = URI.parse("#{Discourse.base_url_no_prefix}#{link[:url]}")
        query = Rack::Utils.parse_query(uri.query)
        query.delete("lang") if link[:locale] == SiteSetting.default_locale
        uri.query = query.presence&.to_query
        { locale: link[:locale], url: uri.to_s }
      end
    end

    def reader_image
      source = @source || @player
      if source&.provider == "youtube" && source.external_id.to_s.match?(/\A[A-Za-z0-9_-]{11}\z/)
        "https://i.ytimg.com/vi/#{source.external_id}/hqdefault.jpg"
      end
    end

    def reader_recording_schema(source)
      url = "#{Discourse.base_url_no_prefix}#{DiscourseTaper.root_path}/recordings/#{source.id}"
      {
        "@type" =>
          source.kind == "video" || source.provider == "youtube" ? "VideoObject" : "MusicRecording",
        "@id" => "#{url}#recording",
        "name" => source.title.presence || source.show.title,
        "url" => url,
        "sameAs" => source.display_url,
        "recordedAt" => {
          "@id" => "#{Discourse.base_url_no_prefix}#{source.show.url}#event",
        },
      }.compact
    end

    def reader_schema
      band_url = "#{Discourse.base_url_no_prefix}#{@band.url}"
      band = {
        "@type" => "MusicGroup",
        "@id" => "#{band_url}#band",
        "name" => @band.name,
        "url" => band_url,
      }
      graph = [band]
      if @show
        event_url = "#{Discourse.base_url_no_prefix}#{@show.url}"
        graph << {
          "@type" => "MusicEvent",
          "@id" => "#{event_url}#event",
          "name" => "#{@band.name} #{@show.label} #{@show.location}",
          "startDate" => @show.date.iso8601,
          "url" => event_url,
          "performer" => {
            "@id" => band["@id"],
          },
          "location" => {
            "@type" => "Place",
            "name" => @show.venue,
            "address" => {
              "@type" => "PostalAddress",
              "addressLocality" => @show.city,
              "addressRegion" => @show.region,
              "addressCountry" => @show.country,
            }.compact,
          },
          "recordedIn" =>
            (@source ? [@source] : @sources || []).map { |s| reader_recording_schema(s) },
        }
      else
        graph << {
          "@type" => "CollectionPage",
          "@id" => @canonical_url,
          "url" => @canonical_url,
          "name" => reader_title,
          "description" => reader_description,
          "about" => {
            "@id" => band["@id"],
          },
        }
      end
      graph << reader_recording_schema(@source) if @source
      if action_name == "band" && @listing_title.nil?
        graph << {
          "@type" => "WebSite",
          "@id" => "#{band_url}#website",
          "url" => band_url,
          "name" => @band.name,
        }
      end
      crumbs = [
        { "@type" => "ListItem", "position" => 1, "name" => @band.name, "item" => band_url },
      ]
      if @show
        crumbs << {
          "@type" => "ListItem",
          "position" => 2,
          "name" => @show.title,
          "item" => "#{Discourse.base_url_no_prefix}#{@show.url}",
        }
      end
      if @source || !@show && @canonical_url != band_url
        crumbs << {
          "@type" => "ListItem",
          "position" => crumbs.size + 1,
          "name" => reader_title,
          "item" => @canonical_url,
        }
      end
      graph << { "@type" => "BreadcrumbList", "itemListElement" => crumbs }
      { "@context" => "https://schema.org", "@graph" => graph }
    end

    # Core emits WebSite only at /; the reader emits it consistently at its canonical URL.
    def render_sitelinks_search_tag
      nil
    end
  end
end
