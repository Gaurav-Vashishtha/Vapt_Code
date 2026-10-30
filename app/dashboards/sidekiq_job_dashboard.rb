require "administrate/base_dashboard"

class SidekiqJobDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    jid: Field::String,
    queue: Field::String,
    class_name: Field::String,
    args: Field::Text,
    retry: Field::Boolean,
    enqueued_at: Field::DateTime,
    started_at: Field::DateTime,
    finished_at: Field::DateTime,
    status: Field::String,
    name: Field::String,
    result: Field::Text,
  }.freeze

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = %i[
    id
    jid
    queue
    class_name
  ].freeze

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = %i[
    id
    jid
    queue
    class_name
    args
    retry
    enqueued_at
    started_at
    finished_at
    status
    name
    result
  ].freeze

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = %i[
    jid
    queue
    class_name
    args
    retry
    enqueued_at
    started_at
    finished_at
    status
    name
    result
  ].freeze

  # COLLECTION_FILTERS
  # a hash that defines filters that can be used while searching via the search
  # field of the dashboard.
  #
  # For example to add an option to search for open resources by typing "open:"
  # in the search field:
  #
  #   COLLECTION_FILTERS = {
  #     open: ->(resources) { resources.where(open: true) }
  #   }.freeze
  COLLECTION_FILTERS = {}.freeze

  # Overwrite this method to customize how sidekiq jobs are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(sidekiq_job)
  #   "SidekiqJob ##{sidekiq_job.id}"
  # end
end
