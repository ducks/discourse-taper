import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class TaperReviewRoute extends DiscourseRoute {
  async model() {
    const [{ suggestions }, { bands }] = await Promise.all([
      ajax("/taper/suggestions.json"),
      ajax("/taper/admin/bands.json"),
    ]);
    return { suggestions, bands };
  }

  titleToken() {
    return i18n("taper.review.title");
  }
}
