# frozen_string_literal: true

require "digest"

module CodForm
  module Engine
    # Deterministic A/B assignment (ARCHITECTURE E.13, OFF-12).
    class AbTest
      class << self
        # test = {"id"=>3, "variants"=>[{"key"=>"a","offer_id"=>12,"weight"=>50}, ...]}; seed = client_id
        # => variant key (String) | nil when the test has no usable variant
        def assign(test:, seed:)
          test = test.is_a?(Hash) ? test : {}
          variants = Array(test["variants"]).select { |v| v.is_a?(Hash) && v["weight"].to_i.positive? && !v["key"].to_s.empty? }
          return nil if variants.empty?

          bucket = Digest::SHA256.hexdigest("#{test['id']}:#{seed}")[0, 8].to_i(16) % 100
          cumulative = 0
          variants.each do |variant|
            cumulative += variant["weight"].to_i
            return variant["key"].to_s if bucket < cumulative
          end
          variants.last["key"].to_s
        end
      end
    end
  end
end
