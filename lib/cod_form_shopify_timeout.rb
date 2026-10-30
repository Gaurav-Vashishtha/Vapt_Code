# frozen_string_literal: true

require "net/http"

# Read time-out for the Shopify Admin GraphQL calls made on behalf of a buyer who is waiting in
# the COD Form (docs/cod-form/ARCHITECTURE.md F.2: "Shopify HTTP read timeout 12 s").
#
# ShopifyAPI::GraphQL.client is one shared client with no per-call option, and every other
# service of the app must keep Net::HTTP's defaults. So the time-out is a thread-local that only
# the form services set:
#
#   CodFormShopifyTimeout.with { client.query(document, variables: variables) }
#
# Outside such a block `current` is nil and the connection is exactly what it was before.
# Lives in lib/ under a top-level name (not CodForm::…) on purpose: it is prepended to a gem
# class once at boot, so it must not be a reloadable (Zeitwerk-managed) constant.
#
# Not covered: the REST (ActiveResource) calls of ShopifyServices::CodOrderCreateService
# (DraftOrder#complete, Order.find) — ActiveResource's time-out is a class-wide setting shared
# with the whole app. Those keep the default.
module CodFormShopifyTimeout
  READ_TIMEOUT = 12
  OPEN_TIMEOUT = 5
  KEY = :cod_form_shopify_read_timeout

  # Prepended to ShopifyAPI::GraphQL::HTTPClient (a GraphQL::Client::HTTP, whose `connection`
  # is the documented extension point).
  module Connection
    def connection
      http = super
      seconds = CodFormShopifyTimeout.current
      if seconds
        http.read_timeout = seconds
        http.open_timeout = [seconds, OPEN_TIMEOUT].min
      end
      http
    end
  end

  module_function

  def with(seconds = READ_TIMEOUT)
    previous = Thread.current[KEY]
    Thread.current[KEY] = seconds
    yield
  ensure
    Thread.current[KEY] = previous
  end

  def current
    Thread.current[KEY]
  end

  # Idempotent. Returns true when the class now carries the hook.
  def install!(klass)
    return false unless klass.is_a?(Class) && klass.method_defined?(:connection)

    klass.prepend(Connection) unless klass.ancestors.include?(Connection)
    true
  end
end
