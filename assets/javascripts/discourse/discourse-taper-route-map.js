// The reviewer's queue and the band admin live in the app; the reader
// surface at /taper is server-rendered and never boots Ember.
export default function () {
  this.route("taper-review", { path: "/taper/review" });
  this.route("taper-bands", { path: "/taper/admin/bands" });
}
