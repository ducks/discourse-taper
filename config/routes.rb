# frozen_string_literal: true

DiscourseTaper::Engine.routes.draw do
  get "/bands" => "shows#bands"
  get "/suggestions" => "suggestions#index"
  post "/suggestions/import" => "suggestions#import"
  post "/suggestions/:id/accept" => "suggestions#accept", :constraints => { id: /\d+/ }
  post "/suggestions/:id/reject" => "suggestions#reject", :constraints => { id: /\d+/ }
  post "/:band/suggest" => "shows#suggest"
  get "/:band" => "shows#band"
  get "/:band/:date" => "shows#show", :constraints => { date: /\d{4}-\d{2}-\d{2}(-\d+)?/ }
end
