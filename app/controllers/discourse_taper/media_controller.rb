# frozen_string_literal: true

module DiscourseTaper
  # Reviewers can take an item off the band's media shelf. It stays in
  # the table, hidden, so a re-run of the importer does not put it back.
  class MediaController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_reviewer

    def destroy
      item = MediaItem.find(params[:id])
      item.update!(hidden: true)
      render json: success_json
    end

    private

    def ensure_reviewer
      raise Discourse::InvalidAccess if !DiscourseTaper.reviewer?(current_user)
    end
  end
end
