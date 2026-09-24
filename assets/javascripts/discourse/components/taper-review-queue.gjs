import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { trackedArray } from "@ember/reactive/collections";
import { cancel, later } from "@ember/runloop";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";
import TaperSuggestionRow from "./taper-suggestion-row";

// The reviewer's queue. Each row is one show with every recording found
// for it, accepted or rejected in one click. Decisions are recorded at
// the top so a reviewer working down a long queue can see what landed.
// A trusted show source (setlist.fm) can be accepted wholesale; that
// runs in a job and the queue refreshes when it reports back.
export default class TaperReviewQueue extends Component {
  @service currentUser;
  @service dialog;
  @service messageBus;

  @tracked importing = null;
  @tracked bulkBusy = false;
  bulk = null;
  pollTimer = null;
  pollsLeft = 0;
  suggestions = trackedArray(this.args.suggestions ?? []);
  decisions = trackedArray();

  constructor() {
    super(...arguments);
    this.messageBus.subscribe(this.channel, this.onMessage);
  }

  willDestroy() {
    super.willDestroy(...arguments);
    this.messageBus.unsubscribe(this.channel, this.onMessage);
    cancel(this.pollTimer);
  }

  // The job reports back on the reviewer's own channel, the Discourse
  // convention for messages meant for one person.
  get channel() {
    return `/taper/review/${this.currentUser.id}`;
  }

  get importers() {
    return ["setlist_fm", "archive_org", "youtube"];
  }

  // Pending new shows per importer, the unit a reviewer may accept in
  // bulk. Member suggestions and recordings never appear here.
  get bulkOrigins() {
    const counts = {};
    for (const s of this.suggestions) {
      if (s.kind === "new_show" && this.importers.includes(s.origin)) {
        counts[s.origin] = (counts[s.origin] ?? 0) + 1;
      }
    }
    return this.importers
      .filter((origin) => counts[origin])
      .map((origin) => ({
        origin,
        count: counts[origin],
        label: i18n(`taper.provider.${origin}`),
      }));
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

  @action
  acceptAll(bulk) {
    this.dialog.yesNoConfirm({
      message: i18n("taper.review.accept_all_confirm", {
        count: bulk.count,
        origin: bulk.label,
      }),
      didConfirm: async () => {
        this.bulkBusy = true;
        try {
          const { queued } = await ajax("/taper/suggestions/accept_all.json", {
            type: "POST",
            data: { origin: bulk.origin },
          });
          this.decisions.unshift({
            label: i18n("taper.review.accept_all_queued", {
              count: queued,
              origin: bulk.label,
            }),
          });
          // The job runs after the response and reports back over
          // MessageBus. Polling the queue is the fallback, and it can
          // tell the same story: the rows that vanished were accepted.
          this.bulk = { origin: bulk.origin, label: bulk.label, start: queued };
          this.pollsLeft = 60;
          this.pollTimer = later(this, this.poll, 2000);
        } catch (e) {
          popupAjaxError(e);
          this.bulkBusy = false;
        }
      },
    });
  }

  pendingFor(origin) {
    return this.bulkOrigins.find((b) => b.origin === origin)?.count ?? 0;
  }

  async poll() {
    if (!this.bulkBusy) {
      return;
    }
    await this.refresh();
    if (!this.bulkBusy) {
      return;
    }
    const left = this.pendingFor(this.bulk.origin);
    if (left === 0) {
      this.finishBulk(this.bulk.start, 0);
    } else if (--this.pollsLeft <= 0) {
      this.finishBulk(this.bulk.start - left, left);
    } else {
      this.pollTimer = later(this, this.poll, 5000);
    }
  }

  finishBulk(accepted, failed) {
    cancel(this.pollTimer);
    this.bulkBusy = false;
    this.decisions.unshift({
      label: i18n("taper.review.accept_all_done", {
        accepted,
        origin: this.bulk.label,
      }),
    });
    if (failed > 0) {
      this.decisions.unshift({
        label: i18n("taper.review.accept_all_failed", { count: failed }),
      });
    }
  }

  @action
  async onMessage(data) {
    if (data?.type !== "bulk_accept" || !this.bulkBusy) {
      return;
    }
    await this.refresh();
    if (this.bulkBusy) {
      this.finishBulk(data.accepted, data.failed);
    }
  }

  async refresh() {
    try {
      const { suggestions } = await ajax("/taper/suggestions.json");
      this.suggestions.splice(0, this.suggestions.length, ...suggestions);
    } catch (e) {
      popupAjaxError(e);
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
        {{#if this.bulkOrigins.length}}
          <div class="taper-review__bulk">
            {{#each this.bulkOrigins as |bulk|}}
              <DButton
                class="btn-small btn-primary taper-review__accept-all"
                @action={{fn this.acceptAll bulk}}
                @disabled={{this.bulkBusy}}
                @icon="check-double"
                @translatedLabel={{i18n
                  "taper.review.accept_all"
                  count=bulk.count
                  origin=bulk.label
                }}
              />
            {{/each}}
          </div>
        {{/if}}
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
