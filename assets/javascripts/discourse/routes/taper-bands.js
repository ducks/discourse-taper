import { ajax } from "discourse/lib/ajax";
import DiscourseRoute from "discourse/routes/discourse";
import { i18n } from "discourse-i18n";

export default class TaperBandsRoute extends DiscourseRoute {
  async model() {
    const { bands } = await ajax("/taper/admin/bands.json");
    return { bands };
  }

  titleToken() {
    return i18n("taper.bands.title");
  }
}
