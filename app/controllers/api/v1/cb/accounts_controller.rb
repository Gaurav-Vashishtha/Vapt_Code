# frozen_string_literal: true

module Api
  module V1
    module Cb
      # A brand's WhatsApp numbers. A brand can have SEVERAL numbers; exactly
      # one is the default (used when a send doesn't pick an account_id).
      # Connecting a number happens on the brand page / connect page (Meta
      # embedded signup needs a browser) — the API manages what's connected.
      class AccountsController < BaseController
        # GET /api/v1/cb/accounts?shop_domain=…
        def index
          accounts = client.whatsapp_accounts.order(is_default: :desc, id: :asc)
          render json: { shop_domain: client.domain, accounts: accounts.map { |a| serialize(a) } }
        end

        # PATCH /api/v1/cb/accounts/:id — rename, or make default.
        def update
          account = client.whatsapp_accounts.find_by(id: params[:id])
          return render_error('account not found', :not_found) if account.nil?

          account.label = params[:label] if params.key?(:label)
          # Setting default true is honoured; the model unsets the siblings.
          account.is_default = true if ActiveModel::Type::Boolean.new.cast(params[:is_default])

          if account.save
            render json: serialize(account)
          else
            render_error(account.errors.full_messages.to_sentence, :unprocessable_entity)
          end
        end

        # DELETE /api/v1/cb/accounts/:id — disconnect the number. Its message
        # logs are kept (detached from the number); another number (if any) is
        # promoted to default.
        def destroy
          account = client.whatsapp_accounts.find_by(id: params[:id])
          return render_error('account not found', :not_found) if account.nil?

          account.destroy!
          render json: { ok: true, numbers_remaining: client.whatsapp_accounts.count }
        end

        private

        def serialize(a)
          {
            account_id: a.id,
            label: a.label,
            is_default: a.is_default,
            status: a.status,
            ready_to_send: a.ready_to_send?,
            display_phone_number: a.display_phone_number,
            verified_name: a.verified_name,
            quality_rating: a.quality_rating,
            registration_state: a.registration_state,
            needs_registration: a.needs_registration?,
            connected_at: a.created_at
          }
        end
      end
    end
  end
end
