# frozen_string_literal: true

module DiscourseTaper
  # The reader's language switch, shared by every server-rendered page.
  # A reader may pick the archive's language with ?lang=, remembered in a
  # cookie for a year. Only locales the plugin is translated into count.
  # Pages served under a pinned language are not put in the anonymous
  # cache, whose key knows nothing about the cookie.
  module ReaderLocale
    def set_reader_locale
      locales = DiscourseTaper.reader_locales
      return if locales.size < 2
      wanted = params[:lang].presence || cookies[:taper_lang].presence
      return if wanted.blank? || !locales.include?(wanted)
      if params[:lang].present?
        cookies[:taper_lang] = { value: wanted, expires: 1.year.from_now, same_site: :lax }
      end
      I18n.locale = wanted
      @reader_locale_pinned = true
    end

    def reader_query
      query = {}
      if controller_name == "shows" && action_name == "band"
        %w[year venue tour].each { |key| query[key] = params[key].to_s if params[key].present? }
      end
      query
    end

    def set_reader_canonical(path)
      query = reader_query
      locale = I18n.locale.to_s
      if DiscourseTaper.reader_locales.include?(locale) && locale != SiteSetting.default_locale
        query["lang"] = locale
      end
      @canonical_path = path
      @canonical_url = "#{Discourse.base_url_no_prefix}#{path}"
      @canonical_url += "?#{query.to_query}" if query.present?
    end

    def locale_links
      path = (@canonical_path.presence || request.path).split("?", 2).first.chomp("/")
      DiscourseTaper.reader_locales.map do |locale|
        query = reader_query.merge("lang" => locale)
        { locale: locale, url: "#{path}?#{query.to_query}", current: I18n.locale.to_s == locale }
      end
    end

    # Reader pages have JSON alternates, not the forum's Markdown topic list.
    def markdown_alternate_url
      nil
    end
  end
end
