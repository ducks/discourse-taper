# frozen_string_literal: true

module DiscourseTaper
  module ReaderSorting
    OPTIONS = {
      "band" => %w[newest oldest],
      "song" => %w[newest oldest],
      "songs" => %w[most_played least_played title recently_played],
      "media" => %w[newest oldest title],
      "show" => %w[added_oldest added_newest title],
    }.freeze

    def set_reader_sort
      @sort_options = OPTIONS.fetch(action_name)
      @sort = @sort_options.include?(params[:sort]) ? params[:sort] : @sort_options.first
    end

    def sorted_songs(songs)
      case @sort
      when "least_played"
        songs.sort_by { |song| [song.count, song.title.downcase, song.slug] }
      when "title"
        songs.sort_by { |song| [song.title.downcase, song.slug] }
      when "recently_played"
        songs.sort_by { |song| [-song.last_date.jd, song.title.downcase, song.slug] }
      else
        songs.sort_by { |song| [-song.count, song.title.downcase, song.slug] }
      end
    end

    def sorted_media(scope)
      case @sort
      when "oldest"
        scope.reorder(Arel.sql("published_on ASC NULLS LAST"), created_at: :asc, id: :asc)
      when "title"
        scope.reorder(Arel.sql("LOWER(title) ASC"), id: :asc)
      else
        scope.reorder(Arel.sql("published_on DESC NULLS LAST"), created_at: :desc, id: :desc)
      end
    end

    def sorted_sources(scope)
      case @sort
      when "added_newest"
        scope.reorder(created_at: :desc, id: :desc)
      when "title"
        scope.reorder(Arel.sql("LOWER(COALESCE(NULLIF(title, ''), provider)) ASC"), id: :asc)
      else
        scope.reorder(created_at: :asc, id: :asc)
      end
    end
  end
end
