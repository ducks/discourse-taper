import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

// Puts the review queue and the band admin in the sidebar's Community
// section for people who can review. Whether they can is decided on the
// server and exposed as taper_reviewer on the current user.
export default {
  name: "taper-review-sidebar",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    const currentUser = container.lookup("service:current-user");
    if (!siteSettings.taper_enabled || !currentUser?.taper_reviewer) {
      return;
    }

    withPluginApi((api) => {
      api.addCommunitySectionLink({
        name: "taper-review",
        route: "taper-review",
        title: i18n("taper.review.sidebar"),
        text: i18n("taper.review.sidebar"),
        icon: "record-vinyl",
      });
      api.addCommunitySectionLink({
        name: "taper-bands",
        route: "taper-bands",
        title: i18n("taper.bands.sidebar"),
        text: i18n("taper.bands.sidebar"),
        icon: "guitar",
      });
    });
  },
};
