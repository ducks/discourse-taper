// The reviewer's queue lives in the app; the reader surface at /taper is
// server-rendered and never boots Ember.
export default function () {
  this.route("taper-review", { path: "/taper/review" });
}
