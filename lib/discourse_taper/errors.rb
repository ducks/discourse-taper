# frozen_string_literal: true

module DiscourseTaper
  # Raised for user-facing failures; carries an i18n key so the controller
  # can render a translated 422.
  class Error < StandardError
    attr_reader :key

    def initialize(key, **args)
      @key = key
      super(I18n.t("taper.errors.#{key}", **args))
    end
  end
end
