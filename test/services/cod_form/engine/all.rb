# frozen_string_literal: true

# Runs every engine test without Rails:  ruby test/services/cod_form/engine/all.rb
require_relative "engine_test_helper"
Dir[File.join(__dir__, "*_test.rb")].sort.each { |file| require file }
