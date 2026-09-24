# frozen_string_literal: true

DiscourseTaper::Engine.routes.draw do
  date = /\d{4}-\d{2}-\d{2}(-\d+)?/

  get "/bands" => "shows#bands"
  get "/suggestions" => "suggestions#index"
  post "/suggestions/import" => "suggestions#import"
  post "/suggestions/accept_all" => "suggestions#accept_all"
  post "/suggestions/:id/accept" => "suggestions#accept", :constraints => { id: /\d+/ }
  post "/suggestions/:id/reject" => "suggestions#reject", :constraints => { id: /\d+/ }

  # Band management (reviewers).
  get "/admin/bands" => "bands#index"
  post "/admin/bands" => "bands#create"
  put "/admin/bands/:id" => "bands#update", :constraints => { id: /\d+/ }
  delete "/admin/bands/:id" => "bands#destroy", :constraints => { id: /\d+/ }

  # Primary band: no band segment. Declared before the band forms so a
  # date is never read as a band slug.
  get "/(.:format)" => "shows#band"
  get "/suggest" => "shows#suggest_form"
  get "/:date" => "shows#show", :constraints => { date: date }
  post "/suggest" => "shows#suggest"

  # Any band, including the primary one, by slug.
  get "/:band/suggest" => "shows#suggest_form"
  post "/:band/suggest" => "shows#suggest"
  get "/:band" => "shows#band"
  get "/:band/:date" => "shows#show", :constraints => { date: date }
end
