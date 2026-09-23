import TaperReviewQueue from "../components/taper-review-queue";

<template>
  <div class="container taper-review-page">
    <TaperReviewQueue @bands={{@model.bands}} @suggestions={{@model.suggestions}} />
  </div>
</template>
