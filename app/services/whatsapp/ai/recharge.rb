# frozen_string_literal: true

module Whatsapp
  module Ai
    module Recharge
      class Error < StandardError; end

      TEST_SHOPIFY_PLANS = %w[partner_test affiliate plus_partner_sandbox staff staff_business].freeze
      PAID_STATUSES = %w[ACTIVE ACCEPTED].freeze
      DEAD_STATUSES = %w[DECLINED EXPIRED].freeze
      RECONCILE_WINDOW = 7.days

      CREATE_MUTATION = <<~GRAPHQL
        mutation($name: String!, $price: MoneyInput!, $returnUrl: URL!, $test: Boolean) {
          appPurchaseOneTimeCreate(name: $name, price: $price, returnUrl: $returnUrl, test: $test) {
            appPurchaseOneTime { id status }
            confirmationUrl
            userErrors { field message }
          }
        }
      GRAPHQL

      STATUS_QUERY = <<~GRAPHQL
        query($id: ID!) {
          node(id: $id) { ... on AppPurchaseOneTime { id status test } }
        }
      GRAPHQL

      module_function

      def start!(shop, pack_key)
        pack = WhatsappAiWallet.pack(pack_key)
        raise Error, 'Unknown credit pack' unless pack

        data = ShopifyGraphql.call(shop, CREATE_MUTATION, {
                                     name: "AI credits - #{ActiveSupport::NumberHelper.number_to_delimited(pack['credits'])} replies",
                                     price: { amount: pack['price_usd'], currencyCode: 'USD' },
                                     returnUrl: return_url(shop),
                                     test: test_charge?(shop)
                                   })
        payload = data['appPurchaseOneTimeCreate'] || {}
        errors = Array(payload['userErrors']).map { |e| e['message'] }.compact
        raise Error, errors.join('; ') if errors.any?

        gid = payload.dig('appPurchaseOneTime', 'id')
        url = payload['confirmationUrl']
        raise Error, 'Shopify did not return a confirmation link' if gid.blank? || url.blank?

        WhatsappAiCreditTransaction.create!(
          shop_id: shop.id, kind: 'purchase', status: 'pending', credits: pack['credits'], pack: pack_key.to_s,
          amount_usd: pack['price_usd'], shopify_charge_gid: gid, confirmation_url: url
        )
        url
      rescue ShopifyGraphql::Error => e
        raise Error, e.message
      end

      def confirm!(shop, charge_id)
        gid = charge_gid(charge_id)
        return nil if gid.nil?

        row = WhatsappAiCreditTransaction.find_by(shop_id: shop.id, shopify_charge_gid: gid)
        return nil unless row

        settle!(shop, row)
      end

      def reconcile_pending!(shop)
        WhatsappAiCreditTransaction.pending.where(shop_id: shop.id, kind: 'purchase')
                                   .where('created_at > ?', RECONCILE_WINDOW.ago)
                                   .find_each { |row| safe_settle(shop, row) }
        WhatsappAiCreditTransaction.pending.where(shop_id: shop.id, kind: 'purchase')
                                   .where('created_at <= ?', RECONCILE_WINDOW.ago)
                                   .find_each do |row|
          next if safe_settle(shop, row)&.status != 'pending'
          next if remote_status(shop, row.shopify_charge_gid).nil?

          WhatsappAiCreditTransaction.where(id: row.id, status: 'pending')
                                     .update_all(status: 'declined', note: 'Not approved in Shopify', updated_at: Time.current)
        end
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Ai::Recharge] reconcile failed shop=#{shop.id}: #{e.class}: #{e.message}")
      end

      def safe_settle(shop, row)
        settle!(shop, row)
      rescue StandardError => e
        Rails.logger.warn("[Whatsapp::Ai::Recharge] settle failed tx=#{row.id}: #{e.class}: #{e.message}")
        nil
      end

      def settle!(shop, row)
        return row unless row.status == 'pending'

        status = remote_status(shop, row.shopify_charge_gid)
        if PAID_STATUSES.include?(status)
          WhatsappAiWallet.for(shop)
          WhatsappAiCreditTransaction.transaction do
            locked = WhatsappAiCreditTransaction.lock.find(row.id)
            next locked unless locked.status == 'pending'

            Wallet.credit!(shop, locked.credits, kind: 'purchase', transaction: locked)
          end
        elsif DEAD_STATUSES.include?(status)
          WhatsappAiCreditTransaction.where(id: row.id, status: 'pending')
                                     .update_all(status: 'declined', note: "Shopify status #{status}", updated_at: Time.current)
          row.reload
        else
          row
        end
      end

      def remote_status(shop, gid)
        data = ShopifyGraphql.call(shop, STATUS_QUERY, { id: gid })
        data.dig('node', 'status').to_s.upcase
      rescue ShopifyGraphql::Error => e
        Rails.logger.warn("[Whatsapp::Ai::Recharge] status lookup failed shop=#{shop.id} gid=#{gid}: #{e.message}")
        nil
      end

      def charge_gid(charge_id)
        raw = charge_id.to_s.strip
        return raw if raw.start_with?('gid://shopify/AppPurchaseOneTime/')
        return nil unless raw.match?(/\A\d+\z/)

        "gid://shopify/AppPurchaseOneTime/#{raw}"
      end

      def test_charge?(shop)
        return true if Rails.env.development? || ENV.fetch("WHATSAPP_AI_TEST_CHARGES", nil).present?

        TEST_SHOPIFY_PLANS.include?(shop.shopify_plan.to_s)
      end

      def return_url(shop)
        handle = ENV.fetch("SHOPIFY_APP_HANDLE", nil).presence || (Rails.env.development? ? 'codkingamandev' : 'cod-verification')
        "https://#{shop.shopify_domain}/admin/apps/#{handle}/features/whatsapp/inbox/ai/credits"
      end

      def auto_recharge!(shop)
        wallet = WhatsappAiWallet.for(shop)
        pack = WhatsappAiWallet.pack(wallet.auto_recharge_pack)
        return :disabled unless wallet.auto_recharge && pack
        return :not_low unless wallet.low?

        row = WhatsappAiCreditTransaction.create!(
          shop_id: shop.id, kind: 'auto_recharge', status: 'processing', credits: pack['credits'],
          pack: wallet.auto_recharge_pack, amount_usd: pack['price_usd'], note: 'Auto-recharge on your plan'
        )
        result = ShopifyServices::UsageChargeApplyService.call(
          shop.shopify_domain, pack['price_usd'], description: "COD King AI credits (#{pack['credits']} replies)"
        )
        if result[:success]
          begin
            Wallet.credit!(shop, pack['credits'], kind: 'auto_recharge', transaction: row)
          rescue StandardError => e
            row.update_columns(status: 'failed', note: "Charged but not credited: #{e.class}")
            SlackNotifyJob.perform_async(":rotating_light: (#{Rails.env}) AI auto-recharge charged but NOT credited shop=#{shop.shopify_domain} tx=#{row.id}: #{e.message}")
            raise
          end
          :charged
        else
          row.update_columns(status: 'failed', note: "Shopify refused: #{result[:reason]}", updated_at: Time.current)
          wallet.update_columns(auto_recharge_failed_at: Time.current, auto_recharge_error: result[:reason].to_s,
                                updated_at: Time.current)
          result[:reason].to_s.to_sym
        end
      end
    end
  end
end
