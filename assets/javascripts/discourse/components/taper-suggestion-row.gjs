import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

export default class TaperSuggestionRow extends Component {
  @tracked note = "";
  @tracked busy = false;
  @tracked showRecordings = false;
  @tracked venue = this.args.suggestion.payload?.venue ?? "";

  get suggestion() {
    return this.args.suggestion;
  }

  get payload() {
    return this.suggestion.payload ?? {};
  }

  get kindLabel() {
    return i18n(`taper.review.kinds.${this.suggestion.kind}`);
  }

  get headline() {
    const p = this.payload;
    if (this.suggestion.kind === "correction" || this.isClaim) {
      return this.suggestion.show?.label;
    }
    return [p.date, p.venue].filter(Boolean).join(" · ");
  }

  get isClaim() {
    return this.suggestion.kind === "claim";
  }

  // A member says a recording is theirs: who, which recording, and who
  // it is credited to today.
  get claim() {
    if (!this.isClaim) {
      return null;
    }
    const source = this.suggestion.source;
    const name = this.suggestion.submitted_by?.username;
    return {
      by: i18n("taper.review.claim_by", { name: `@${name}` }),
      title:
        source?.title || i18n(`taper.provider.${source?.provider ?? "link"}`),
      url: source?.url,
      current: source?.taper_name
        ? i18n("taper.review.claim_current", { name: source.taper_name })
        : i18n("taper.review.claim_uncredited"),
    };
  }

  get location() {
    return [this.payload.city, this.payload.region].filter(Boolean).join(", ");
  }

  get isNewShow() {
    return this.suggestion.kind === "new_show";
  }

  // How the importer resolved the venue, if it did: a learned alias, a
  // standard abbreviation, or a trigram near-match with its score.
  get venueMatch() {
    const match = this.payload.venue_match;
    if (!match) {
      return null;
    }
    return i18n(`taper.review.venue_match.${match.method}`, {
      score: match.score,
    });
  }

  get bandName() {
    const band = this.suggestion.band;
    return band && !band.primary ? band.name : null;
  }

  get origin() {
    if (this.suggestion.submitted_by) {
      return `@${this.suggestion.submitted_by.username}`;
    }
    return i18n("taper.review.from_importer", {
      name: i18n(`taper.provider.${this.suggestion.origin}`),
    });
  }

  // Other spellings the importer saw for this venue, most common first,
  // excluding the one it chose.
  get otherSpellings() {
    const spellings = this.payload.venue_spellings ?? {};
    return Object.entries(spellings)
      .filter(([venue]) => venue !== this.payload.venue)
      .sort((a, b) => b[1] - a[1])
      .map(([venue, count]) => `${venue} (${count})`);
  }

  get recordings() {
    const p = this.payload;
    const list = Array.isArray(p.sources)
      ? p.sources
      : p.source?.url
        ? [p.source]
        : p.url
          ? [p]
          : [];
    return list.map((s) => ({
      ...s,
      kindLabel: i18n(`taper.kind.${s.kind ?? "unknown"}`),
      providerLabel: i18n(`taper.provider.${s.provider ?? "link"}`),
      duration: formatDuration(s.duration_seconds),
    }));
  }

  get changes() {
    const changes = this.payload.changes ?? {};
    return Object.entries(changes).map(([field, value]) => ({
      field,
      value: Array.isArray(value)
        ? value.map((song) => [song.title, song.notes].filter(Boolean).join(" ")).join(", ")
        : value,
    }));
  }

  @action
  updateNote(event) {
    this.note = event.target.value;
  }

  @action
  updateVenue(event) {
    this.venue = event.target.value;
  }

  @action
  toggleRecordings() {
    this.showRecordings = !this.showRecordings;
  }

  @action
  async accept() {
    await this.decide("accept", (result) => ({
      label: i18n("taper.review.accepted", { label: this.headline }),
      url: result.show_url,
    }));
  }

  @action
  async reject() {
    await this.decide("reject", () => ({
      label: i18n("taper.review.rejected", { label: this.headline }),
    }));
  }

  async decide(verb, describe) {
    this.busy = true;
    try {
      const data = { note: this.note };
      if (verb === "accept" && this.isNewShow) {
        data.venue = this.venue;
      }
      const result = await ajax(
        `/taper/suggestions/${this.suggestion.id}/${verb}.json`,
        {
        type: "POST",
        data,
      });
      this.args.onDecided(this.suggestion, describe(result));
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.busy = false;
    }
  }

  <template>
    <article class="taper-suggestion taper-suggestion--{{this.suggestion.kind}}">
      <header class="taper-suggestion__header">
        <span class="taper-suggestion__kind">{{this.kindLabel}}</span>
        <strong class="taper-suggestion__headline">{{this.headline}}</strong>
        {{#if this.location}}<span class="taper-suggestion__location">{{this.location}}</span>{{/if}}
        {{#if this.bandName}}<span class="taper-suggestion__band">{{this.bandName}}</span>{{/if}}
        <span class="taper-suggestion__origin">{{this.origin}}</span>
      </header>

      {{#if this.venueMatch}}
        <p class="taper-suggestion__venue-match">{{this.venueMatch}}</p>
      {{/if}}

      {{#if this.otherSpellings.length}}
        <p class="taper-suggestion__spellings">
          {{i18n "taper.review.also_seen_as"}}
          {{#each this.otherSpellings as |s|}}<span>{{s}}</span>{{/each}}
        </p>
      {{/if}}

      {{#if this.suggestion.note}}
        <p class="taper-suggestion__note">{{this.suggestion.note}}</p>
      {{/if}}

      {{#if this.claim}}
        <div class="taper-suggestion__claim">
          <span>{{this.claim.by}}</span>
          <a href={{this.claim.url}} rel="noopener noreferrer" target="_blank">{{this.claim.title}}</a>
          <span>{{this.claim.current}}</span>
        </div>
      {{/if}}

      {{#if this.changes.length}}
        <dl class="taper-suggestion__changes">
          {{#each this.changes as |c|}}
            <dt>{{c.field}}</dt>
            <dd>{{c.value}}</dd>
          {{/each}}
        </dl>
      {{/if}}

      {{#if this.recordings.length}}
        <button
          class="btn-flat taper-suggestion__toggle"
          type="button"
          {{on "click" this.toggleRecordings}}
        >
          {{i18n "taper.review.recordings_count" count=this.recordings.length}}
        </button>
        {{#if this.showRecordings}}
          <ul class="taper-suggestion__recordings">
            {{#each this.recordings as |r|}}
              <li>
                <span class="taper-source__kind">{{r.kindLabel}}</span>
                <a href={{r.url}} rel="noopener noreferrer" target="_blank">{{if r.title r.title r.providerLabel}}</a>
                <span class="taper-suggestion__recording-meta">
                  {{r.providerLabel}}
                  {{#if r.format}}· {{r.format}}{{/if}}
                  {{#if r.duration}}· {{r.duration}}{{/if}}
                  {{#if r.taper_name}}· {{r.taper_name}}{{/if}}
                </span>
              </li>
            {{/each}}
          </ul>
        {{/if}}
      {{/if}}

      <footer class="taper-suggestion__actions">
        {{#if this.isNewShow}}
          <label class="taper-suggestion__venue">
            {{i18n "taper.review.venue"}}
            <input
              class="taper-suggestion__venue-input"
              type="text"
              value={{this.venue}}
              {{on "input" this.updateVenue}}
            />
          </label>
        {{/if}}
        <input
          class="taper-suggestion__review-note"
          placeholder={{i18n "taper.review.note_placeholder"}}
          type="text"
          value={{this.note}}
          {{on "input" this.updateNote}}
        />
        <DButton
          class="btn-primary taper-suggestion__accept"
          @action={{this.accept}}
          @disabled={{this.busy}}
          @icon="check"
          @label="taper.review.accept"
        />
        <DButton
          class="btn-danger taper-suggestion__reject"
          @action={{this.reject}}
          @disabled={{this.busy}}
          @icon="xmark"
          @label="taper.review.reject"
        />
      </footer>
    </article>
  </template>
}

function formatDuration(seconds) {
  if (!seconds) {
    return null;
  }
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  return h > 0 ? `${h}h ${String(m).padStart(2, "0")}m` : `${m}m`;
}
