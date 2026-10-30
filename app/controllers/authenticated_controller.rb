# frozen_string_literal: true

class AuthenticatedController < ApplicationController
    # protect_from_forgery with: :null_session
  before_action :set_shop
  include ShopifyApp::Authenticated
end
