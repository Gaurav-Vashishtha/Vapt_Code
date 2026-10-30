class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true

  # Avoid PG "cached plan must not change result type" when the schema changes while
  # the process keeps running (e.g. after db:migrate without restarting the server).
  self.enumerate_columns_in_select_statements = true
end
