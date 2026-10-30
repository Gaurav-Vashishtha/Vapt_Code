# frozen_string_literal: true

# Runs every plain-minitest WS8 test (no Rails, no database):
#   ruby test/services/cod_form/analytics/all.rb
here = File.expand_path("..", __dir__)
%w[analytics tracking integrations abandonment].each do |folder|
  Dir[File.join(here, folder, "*_test.rb")].sort.each { |file| require file }
end
