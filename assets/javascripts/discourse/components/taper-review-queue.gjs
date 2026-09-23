import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { trackedArray } from "@ember/reactive/collections";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import TaperSuggestionRow from "./taper-suggestion-row";

// The reviewer's queue. Each row is one show with every recording found
// for it, accepted or rejected in one click. Decisions are recorded at
// the top so a reviewer working down a long queue can see what landed.
export default class TaperReviewQueue extends Component {
  @tracked importing = null;
  suggestions = trackedArray(this.args.suggestions ?? []);
  decisions = trackedArray();

  get importers() {
    return ["archive_org", "youtube"];
  }

  @action
  decided(suggestion, result) {
    this.suggestions.splice(this.suggestions.indexOf(suggestion), 1);
    this.decisions.unshift(result);
  }

  @action
  async runImporter(band, importer) {
    this.importing = `${band.id}:${importer}`;
    try {
      await ajax("/taper/suggestions/import.json", {
        type: "POST",
        data: { band_id: band.id, importer },
      });
      this.decisions.unshift({
        label: i18n("taper.review.import_queued", {
          importer: i18n(`taper.provider.${importer}`),
          band: band.name,
        }),
      });
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.importing = null;
    }
  }

  <template>
    <div class="taper-review">
      <header class="taper-review__header">
        <h1>{{i18n "taper.review.title"}}</h1>
        <div class="taper-review__importers">
          {{#each @bands as |band|}}
            {{#each this.importers as |importer|}}
              <DButton
                class="btn-small btn-default"
                @action={{fn this.runImporter band importer}}
                @disabled={{this.importing}}
                @icon="rotate"
                @translatedLabel={{i18n
                  "taper.review.run_importer"
                  importer=(i18n (concat "taper.provider." importer))
                  band=band.name
                }}
              />
            {{/each}}
          {{/each}}
        </div>
      </header>

      {{#if this.decisions.length}}
        <ul class="taper-review__decisions">
          {{#each this.decisions as |d|}}
            <li>
              {{d.label}}
              {{#if d.url}}<a href={{d.url}}>{{i18n "taper.review.view_show"}}</a>{{/if}}
            </li>
          {{/each}}
        </ul>
      {{/if}}

      {{#if this.suggestions.length}}
        <p class="taper-review__count">
          {{i18n "taper.review.pending_count" count=this.suggestions.length}}
        </p>
        {{#each this.suggestions as |suggestion|}}
          <TaperSuggestionRow @onDecided={{this.decided}} @suggestion={{suggestion}} />
        {{/each}}
      {{else}}
        <p class="taper-review__empty">{{i18n "taper.review.empty"}}</p>
      {{/if}}
    </div>
  </template>
}

function concat(a, b) {
  return `${a}${b}`;
}
