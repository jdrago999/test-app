
require 'bundler/setup'
require 'sinatra'
require 'sinatra/base'
require 'active_support/all'

module MyService
  class App < Sinatra::Application
    before do
      content_type :json
    end

    get '/' do
      {hello: :world}.to_json
    end
  end
end

MyService::App.run!
