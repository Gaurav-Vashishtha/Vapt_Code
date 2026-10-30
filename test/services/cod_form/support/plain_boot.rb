# frozen_string_literal: true

# First line of a plain-minitest file of the COD Form module that loads its code with
# `require_relative` and depends on sibling classes:
#
#   require_relative "support/plain_boot"      (adjust the relative path)
#
# Such a file runs two ways:
#   * `ruby test/…_test.rb` — no Rails at all: every file `require_relative`s its siblings itself
#     (the `unless defined?(::Rails)` guards in app/services/cod_form/**).
#   * `bin/rails test test/…_test.rb` — the constant ::Rails exists, so those guards skip the
#     sibling requires and rely on Zeitwerk. That only works once the application is booted,
#     which a test file normally gets from `require "test_helper"`. Without it the first sibling
#     constant is a NameError (seen for recovery_link_test, metafield_sync_service_test and
#     tracking/payloads_test when each is run on its own).
# Same idea as test/services/cod_form/engine/engine_test_helper.rb.
if defined?(::Rails)
  booted = ::Rails.respond_to?(:application) && ::Rails.application && ::Rails.application.initialized?
  require "test_helper" unless booted
end

require "minitest/autorun"
