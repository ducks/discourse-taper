import Component from "@glimmer/component";
import dIcon from "discourse/ui-kit/helpers/d-icon";
import { i18n } from "discourse-i18n";

// The show record, rendered at the top of its topic: setlist and every
// known recording. The first post is only a summary; this is the live view.
export default class TaperShowCard extends Component {
  static shouldRender(outletArgs) {
    return !!outletArgs.model?.taper_show;
  }

  get show() {
    return this.args.outletArgs.model.taper_show;
  }

  get sources() {
    return (this.show.sources ?? []).map((source) => ({
      ...source,
      kindLabel: i18n(`taper.kind.${source.kind}`),
      providerLabel: i18n(`taper.provider.${source.provider}`),
      duration: formatDuration(source.duration_seconds),
      tapedBy: source.taper
        ? i18n("taper.card.taped_by", { name: source.taper })
        : null,
    }));
  }

  <template>
    <section class="taper-show-card">
      <header class="taper-show-card__header">
        <span class="taper-show-card__icon">{{dIcon "record-vinyl"}}</span>
        <div class="taper-show-card__heading">
          <a class="taper-show-card__band" href={{this.show.band.url}}>{{this.show.band.name}}</a>
          <div class="taper-show-card__where">
            <strong>{{this.show.label}}</strong>
            <span>{{this.show.location}}</span>
            {{#if this.show.tour}}<span class="taper-show-card__tour">{{this.show.tour}}</span>{{/if}}
          </div>
        </div>
        <a class="btn btn-default btn-small" href={{this.show.band.url}}>{{i18n "taper.card.browse"}}</a>
      </header>

      <div class="taper-show-card__body">
        {{#if this.show.setlist.length}}
          <div class="taper-show-card__setlist">
            <h3>{{i18n "taper.card.setlist"}}</h3>
            <ol>
              {{#each this.show.setlist as |song|}}
                <li>
                  {{song.title}}
                  {{#if song.notes}}<span class="taper-show-card__song-notes">{{song.notes}}</span>{{/if}}
                </li>
              {{/each}}
            </ol>
          </div>
        {{/if}}

        <div class="taper-show-card__sources">
          <h3>{{i18n "taper.card.sources"}}</h3>
          {{#if this.sources.length}}
            <ul>
              {{#each this.sources as |source|}}
                <li class="taper-source taper-source--{{source.kind}}">
                  <span class="taper-source__kind">{{source.kindLabel}}</span>
                  <a class="taper-source__title" href={{source.url}} rel="noopener noreferrer" target="_blank">
                    {{if source.title source.title source.providerLabel}}
                  </a>
                  <span class="taper-source__meta">
                    {{source.providerLabel}}
                    {{#if source.format}}· {{source.format}}{{/if}}
                    {{#if source.duration}}· {{source.duration}}{{/if}}
                    {{#if source.tapedBy}}· {{source.tapedBy}}{{/if}}
                  </span>
                  {{#if source.lineage}}
                    <details class="taper-source__lineage"><summary>lineage</summary>{{source.lineage}}</details>
                  {{/if}}
                </li>
              {{/each}}
            </ul>
          {{else}}
            <p class="taper-show-card__empty">{{i18n "taper.card.no_sources"}}</p>
          {{/if}}
        </div>
      </div>
    </section>
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
