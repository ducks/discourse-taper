import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { trackedArray } from "@ember/reactive/collections";
import { LinkTo } from "@ember/routing";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import TaperBandForm from "./taper-band-form";

// Bands, for reviewers: the name and blurb the reader shows, and the
// identifiers each importer needs. One form per band, plus one for a
// new band. The first band created is the primary one; another can be
// made primary here and the reader's short URLs follow it.
export default class TaperBandAdmin extends Component {
  @tracked adding = false;
  bands = trackedArray(this.args.bands ?? []);

  @action
  startAdding() {
    this.adding = true;
  }

  @action
  cancelAdding() {
    this.adding = false;
  }

  @action
  created(band) {
    this.bands.push(band);
    this.adding = false;
  }

  @action
  updated(band) {
    const index = this.bands.findIndex((b) => b.id === band.id);
    if (index >= 0) {
      this.bands.splice(index, 1, band);
    }
    if (band.primary) {
      this.bands.forEach((b, i) => {
        if (b.id !== band.id && b.primary) {
          this.bands.splice(i, 1, { ...b, primary: false });
        }
      });
    }
  }

  @action
  deleted(band) {
    const index = this.bands.findIndex((b) => b.id === band.id);
    if (index >= 0) {
      this.bands.splice(index, 1);
    }
  }

  <template>
    <div class="taper-bands">
      <header class="taper-bands__header">
        <h1>{{i18n "taper.bands.title"}}</h1>
        <div class="taper-bands__actions">
          <LinkTo class="btn btn-flat" @route="taper-review">
            {{i18n "taper.review.title"}}
          </LinkTo>
          <DButton
            class="btn-primary taper-bands__add"
            @action={{this.startAdding}}
            @disabled={{this.adding}}
            @icon="plus"
            @label="taper.bands.add"
          />
        </div>
      </header>
      <p class="taper-bands__help">{{i18n "taper.bands.help"}}</p>

      {{#if this.adding}}
        <TaperBandForm @onCancel={{this.cancelAdding}} @onSaved={{this.created}} />
      {{/if}}

      {{#each this.bands key="id" as |band|}}
        <TaperBandForm
          @band={{band}}
          @onDeleted={{this.deleted}}
          @onSaved={{this.updated}}
        />
      {{else}}
        {{#unless this.adding}}
          <p class="taper-bands__empty">{{i18n "taper.bands.empty"}}</p>
        {{/unless}}
      {{/each}}
    </div>
  </template>
}
