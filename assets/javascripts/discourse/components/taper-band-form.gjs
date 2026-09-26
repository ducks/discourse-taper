import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import DButton from "discourse/ui-kit/d-button";
import { i18n } from "discourse-i18n";

const TEXT_FIELDS = ["name", "slug", "description"];
const IMPORTER_FIELDS = [
  "archive_org_collection",
  "archive_org_query",
  "youtube_channel_id",
  "youtube_search_query",
  "setlistfm_artist_name",
];

// One band's settings, editable in place. Without @band it is the form
// for a new band.
export default class TaperBandForm extends Component {
  @service dialog;

  @tracked busy = false;
  @tracked saved = false;
  @tracked draft = this.blank();

  get band() {
    return this.args.band;
  }

  get isNew() {
    return !this.args.band;
  }

  get textFields() {
    return TEXT_FIELDS.map((field) => this.fieldFor(field));
  }

  get importerFields() {
    return IMPORTER_FIELDS.map((field) => this.fieldFor(field));
  }

  blank() {
    const band = this.args.band ?? {};
    const draft = {};
    for (const field of [...TEXT_FIELDS, "footer", ...IMPORTER_FIELDS]) {
      draft[field] = band[field] ?? "";
    }
    draft.auto_accept_recordings = band.auto_accept_recordings ?? false;
    return draft;
  }

  fieldFor(field) {
    return {
      name: field,
      value: this.draft[field],
      label: i18n(`taper.bands.fields.${field}`),
      hint: i18n(`taper.bands.hints.${field}`),
    };
  }

  @action
  update(field, event) {
    this.draft = { ...this.draft, [field]: event.target.value };
    this.saved = false;
  }

  @action
  toggle(field, event) {
    this.draft = { ...this.draft, [field]: event.target.checked };
    this.saved = false;
  }

  @action
  async save() {
    this.busy = true;
    try {
      const data = { ...this.draft };
      const result = this.isNew
        ? await ajax("/taper/admin/bands.json", { type: "POST", data })
        : await ajax(`/taper/admin/bands/${this.band.id}.json`, {
            type: "PUT",
            data,
          });
      this.saved = true;
      this.args.onSaved?.(result.band);
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.busy = false;
    }
  }

  @action
  async makePrimary() {
    this.busy = true;
    try {
      const result = await ajax(`/taper/admin/bands/${this.band.id}.json`, {
        type: "PUT",
        data: { primary: "true" },
      });
      this.args.onSaved?.(result.band);
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.busy = false;
    }
  }

  @action
  remove() {
    this.dialog.deleteConfirm({
      message: i18n("taper.bands.delete_confirm", { name: this.band.name }),
      didConfirm: async () => {
        this.busy = true;
        try {
          await ajax(`/taper/admin/bands/${this.band.id}.json`, {
            type: "DELETE",
          });
          this.args.onDeleted?.(this.band);
        } catch (e) {
          popupAjaxError(e);
        } finally {
          this.busy = false;
        }
      },
    });
  }

  <template>
    <form class="taper-band-form" {{on "submit" this.save}}>
      <header class="taper-band-form__header">
        <h2>
          {{#if this.isNew}}
            {{i18n "taper.bands.new"}}
          {{else}}
            {{this.band.name}}
            {{#if this.band.primary}}
              <span class="taper-band-form__primary">{{i18n "taper.bands.primary"}}</span>
            {{/if}}
          {{/if}}
        </h2>
        {{#unless this.isNew}}
          <span class="taper-band-form__meta">
            <a href={{this.band.url}}>{{this.band.url}}</a>
            · {{i18n "taper.bands.show_count" count=this.band.show_count}}
          </span>
        {{/unless}}
      </header>

      <div class="taper-band-form__grid">
        {{#each this.textFields key="name" as |field|}}
          <label class="taper-band-form__field">
            <span>{{field.label}}</span>
            <input
              class="taper-band-form__input"
              data-field={{field.name}}
              type="text"
              value={{field.value}}
              {{on "input" (fn this.update field.name)}}
            />
            <small>{{field.hint}}</small>
          </label>
        {{/each}}
        <label class="taper-band-form__field taper-band-form__field--wide">
          <span>{{i18n "taper.bands.fields.footer"}}</span>
          <textarea
            class="taper-band-form__input"
            data-field="footer"
            rows="4"
            {{on "input" (fn this.update "footer")}}
          >{{this.draft.footer}}</textarea>
          <small>{{i18n "taper.bands.hints.footer"}}</small>
        </label>
      </div>

      <h3>{{i18n "taper.bands.importers"}}</h3>
      <div class="taper-band-form__grid">
        {{#each this.importerFields key="name" as |field|}}
          <label class="taper-band-form__field">
            <span>{{field.label}}</span>
            <input
              class="taper-band-form__input"
              data-field={{field.name}}
              type="text"
              value={{field.value}}
              {{on "input" (fn this.update field.name)}}
            />
            <small>{{field.hint}}</small>
          </label>
        {{/each}}
        <label class="taper-band-form__field taper-band-form__field--wide taper-band-form__check">
          <span>
            <input
              checked={{this.draft.auto_accept_recordings}}
              data-field="auto_accept_recordings"
              type="checkbox"
              {{on "change" (fn this.toggle "auto_accept_recordings")}}
            />
            {{i18n "taper.bands.fields.auto_accept_recordings"}}
          </span>
          <small>{{i18n "taper.bands.hints.auto_accept_recordings"}}</small>
        </label>
      </div>

      <footer class="taper-band-form__actions">
        <DButton
          class="btn-primary taper-band-form__save"
          @action={{this.save}}
          @disabled={{this.busy}}
          @icon="check"
          @label={{if this.isNew "taper.bands.create" "taper.bands.save"}}
        />
        {{#if this.saved}}
          <span class="taper-band-form__saved">{{i18n "taper.bands.saved"}}</span>
        {{/if}}
        {{#if this.isNew}}
          <DButton
            class="btn-flat"
            @action={{@onCancel}}
            @disabled={{this.busy}}
            @label="taper.bands.cancel"
          />
        {{else}}
          {{#unless this.band.primary}}
            <DButton
              class="btn-default taper-band-form__make-primary"
              @action={{this.makePrimary}}
              @disabled={{this.busy}}
              @icon="star"
              @label="taper.bands.make_primary"
            />
          {{/unless}}
          <DButton
            class="btn-danger taper-band-form__delete"
            @action={{this.remove}}
            @disabled={{this.busy}}
            @icon="trash-can"
            @label="taper.bands.delete"
          />
        {{/if}}
      </footer>
    </form>
  </template>
}
