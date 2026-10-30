# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class ReportsController < BaseController
        def show
          render json: ::Whatsapp::Inbox::Report.call(@shop)
        end
      end
    end
  end
end
