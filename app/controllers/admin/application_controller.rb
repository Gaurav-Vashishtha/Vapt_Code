# All Administrate controllers inherit from this
# `Administrate::ApplicationController`, making it the ideal place to put
# authentication logic or other before_actions.
#
# If you want to add pagination or other controller-level concerns,
# you're free to overwrite the RESTful controller actions.
module Admin
  class ApplicationController < Administrate::ApplicationController
    before_action :authenticate_admin
   
    def authenticate_admin
      http_basic_authenticate_or_request_with(
        name: ENV.fetch("ADMIN_USER", nil),
        password: ENV.fetch("ADMIN_PASS", nil)
      )
    end

    def default_sorting_attribute
      :id
    end

    def default_sorting_direction
      :desc
    end

    # Override this value to specify the number of elements to display at a time
    # on index pages. Defaults to 20.
    # def records_per_page
    #   params[:per_page] || 20
    # end
  end
end
