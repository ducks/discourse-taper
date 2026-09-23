import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";

// Puts the review queue in the sidebar's Community section for people
// who can actually review: staff, or members of the reviewer groups.
export default {
  name: "taper-review-sidebar",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");
    const currentUser = container.lookup("service:current-user");
    if (!siteSettings.taper_enabled || !currentUser) {
      return;
    }

    const allowed = (siteSettings.taper_reviewer_groups || "")
      .toString()
      .split("|")
      .filter(Boolean)
      .map(Number);
    const isReviewer =
      currentUser.staff ||
      (currentUser.groups || []).some((group) => allowed.includes(group.id));
    if (!isReviewer) {
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
    });
  },
};
