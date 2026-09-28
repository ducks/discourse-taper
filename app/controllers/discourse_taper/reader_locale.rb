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

    # The language switch: the same page in each reader locale. The engine
    # mounts the front door at "/taper/"; link the canonical path without
    # the slash.
    def locale_links
      path = (@canonical_path.presence || request.path).sub(/\?.*/, "").sub(%r{(?<=.)/\z}, "")
      DiscourseTaper.reader_locales.map do |locale|
        query = request.query_parameters.merge("lang" => locale)
        { locale: locale, url: "#{path}?#{query.to_query}", current: I18n.locale.to_s == locale }
      end
    end
  end
end
