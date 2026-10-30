# frozen_string_literal: true

module Api
  module Whatsapp
    module Inbox
      class CustomersController < BaseController
        PAYMENT_LINK_ERRORS = {
          not_cod: 'This is not a cash on delivery order',
          not_pending: 'This order is no longer waiting for confirmation',
          disabled: 'Prepaid reminders are turned off for your store',
          not_eligible: 'Approve a WhatsApp prepaid template to send payment links',
          paused: 'Prepaid messages are paused',
          rate_limited: 'A payment link was sent for this order in the last 10 minutes',
          mismatch: 'This order does not belong to this customer',
          send_failed: 'The payment link could not be sent. Try again.'
        }.freeze

        before_action :load_conversation

        def show
          render json: ::Whatsapp::Inbox::CustomerContext.call(@conversation)
        end

        def payment_link
          raw_id = params[:order_confirmation_id].to_s
          return render_error('mismatch', PAYMENT_LINK_ERRORS[:mismatch]) unless raw_id.match?(/\A\d+\z/)

          order = OrderConfirmation.find_by(id: raw_id.to_i, shop_id: @shop.id)
          return render_error('mismatch', PAYMENT_LINK_ERRORS[:mismatch]) unless order

          result = ::Whatsapp::Inbox::PaymentLinkSender.call(conversation: @conversation, order_confirmation: order, agent: current_agent)
          return render json: { ok: true } if result == :sent

          code = PAYMENT_LINK_ERRORS.key?(result) ? result : :send_failed
          render_error(code.to_s, PAYMENT_LINK_ERRORS[code])
        end
      end
    end
  end
end
