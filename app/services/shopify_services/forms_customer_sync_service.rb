# frozen_string_literal: true

module ShopifyServices
  # Built for Shopify (Forms): Admin GraphQL segments, customerSegmentMembers, customerCreate/customerUpdate
  # after COD form / OTP flows. Called asynchronously via CodFormCustomerSyncJob.
  #
  # Always returns a Hash (for logging / debugging); see keys :success, :customer, :segments, etc.
  class FormsCustomerSyncService
    def self.call(shop, phone:, email: nil, first_name: nil, last_name: nil)
      phone = phone.to_s.strip
      return { success: false, error: "shop_blank" } if shop.blank?
      return { success: false, error: "phone_blank" } if phone.blank?

      shop.init_session
      client = ShopifyAPI::GraphQL.client
      new(client, shop).sync(
        phone: phone,
        email: email.to_s.strip.presence,
        first_name: first_name.to_s.strip.presence,
        last_name: last_name.to_s.strip.presence
      )
    end

    def initialize(client, shop)
      @client = client
      @shop = shop
    end

    def sync(phone:, email:, first_name:, last_name:)
      result = {
        success: true,
        shop_id: @shop.id,
        shopify_domain: @shop.shopify_domain,
        segments: nil,
        customer_segment_members: nil,
        customer: nil
      }

      result[:segments], result[:customer_segment_members] = touch_segment_queries
      result[:customer] = upsert_customer(phone: phone, email: email, first_name: first_name, last_name: last_name)

      cust = result[:customer]
      # Proof of Shopify write: Admin returns customer GID on success.
      result[:success] = cust[:ok] == true && cust[:customer_id].present?

      result
    rescue StandardError => e
      Rails.logger.warn "[FormsCustomerSyncService] shop_id=#{@shop.id} #{e.class}: #{e.message}"
      {
        success: false,
        shop_id: @shop.id,
        shopify_domain: @shop.shopify_domain,
        error_class: e.class.name,
        error: e.message
      }
    end

    private

    def touch_segment_queries
      q_segments = @client.parse(<<~GRAPHQL)
        query {
          segments(first: 1) {
            edges {
              node {
                id
                name
              }
            }
          }
        }
      GRAPHQL
      seg_resp = @client.query(q_segments)
      seg_id = seg_resp&.data&.segments&.edges&.first&.node&.id
      seg_summary = summarize_response(seg_resp, probe: ->(_d) { seg_id })

      # customerSegmentMembers requires one of: segmentId, queryId, or query.
      q_members = @client.parse(<<~GRAPHQL)
        query ($segmentId: ID!) {
          customerSegmentMembers(first: 1, segmentId: $segmentId) {
            edges {
              node {
                id
              }
            }
          }
        }
      GRAPHQL
      mem_resp =
        if seg_id.present?
          @client.query(q_members, variables: { "segmentId" => seg_id })
        else
          nil
        end
      mem_summary = summarize_response(mem_resp, probe: ->(d) { d&.customer_segment_members&.edges&.first&.node&.id })

      [seg_summary, mem_summary]
    rescue StandardError => e
      Rails.logger.warn "[FormsCustomerSyncService] segment touch shop_id=#{@shop.id}: #{e.message}"
      [
        { ok: false, error: e.message },
        { ok: false, error: e.message }
      ]
    end

    def summarize_response(resp, probe:)
      top = graphql_top_level_errors(resp)
      ok = top.empty? && resp&.data.present?
      sample_id = nil
      begin
        sample_id = probe.call(resp.data) if ok && resp.data
      rescue StandardError
        sample_id = nil
      end
      { ok: ok, graphql_errors: top, sample_id: sample_id }
    end

    def graphql_top_level_errors(resp)
      return [] if resp.nil?

      if resp.respond_to?(:errors) && resp.errors.present?
        errs = resp.errors
        if errs.respond_to?(:messages) && errs.messages.is_a?(Hash)
          return errs.messages.values.flatten.map { |m| m.to_s }.compact
        end
        if errs.is_a?(Hash)
          return errs.values.flatten.map { |e| e.try(:message) || e.to_s }.compact
        end
        if errs.respond_to?(:map)
          return errs.map { |e| e.try(:message) || e.to_s }.compact
        end
      end
      []
    end

    def upsert_customer(phone:, email:, first_name:, last_name:)
      gid = find_customer_gid(phone: phone, email: email)
      input = build_input(phone: phone, email: email, first_name: first_name, last_name: last_name)

      if gid.present?
        merged = input.merge(id: gid)
        out = run_customer_update(merged)
        out.merge(action: "update", matched_customer_id: gid)
      else
        out = run_customer_create(input)
        out.merge(action: "create", matched_customer_id: nil)
      end
    end

    def build_input(phone:, email:, first_name:, last_name:)
      h = {}
      h[:phone] = phone if phone.present?
      h[:email] = email if email.present?
      h[:firstName] = first_name if first_name.present?
      h[:lastName] = last_name if last_name.present?
      h
    end

    def find_customer_gid(phone:, email:)
      q = @client.parse(<<~GRAPHQL)
        query ($query: String!) {
          customers(first: 1, query: $query) {
            edges {
              node {
                id
              }
            }
          }
        }
      GRAPHQL

      phone_compact = phone.gsub(/\s+/, "")
      # Prefer phone match first to avoid updating the wrong customer when
      # email belongs to a different customer than the phone.
      search_terms = []
      search_terms << %(phone:#{escape_search_term(phone_compact)}) if phone_compact.present?
      search_terms << %(email:"#{escape_search_term(email)}") if email.present?

      search_terms.each do |term|
        resp = @client.query(q, variables: { "query" => term })
        next if resp&.data.blank?

        edges = resp.data.customers&.edges
        next if edges.blank?

        id = edges.first&.node&.id
        return id if id.present?
      end

      nil
    end

    def escape_search_term(value)
      value.to_s.gsub('\\', '\\\\').gsub('"', '\\"')
    end

    def run_customer_create(input)
      if input.except(:id).blank?
        return { ok: false, skipped: true, reason: "empty_input", customer_id: nil, user_errors: [], graphql_errors: [] }
      end

      q = @client.parse(<<~GRAPHQL)
        mutation ($input: CustomerInput!) {
          customerCreate(input: $input) {
            customer {
              id
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL
      resp = @client.query(q, variables: { "input" => input.stringify_keys })
      out = summarize_mutation(resp, "customerCreate")
      if out[:user_errors].any? { |m| m.to_s.downcase.include?("phone has already been taken") } && input[:phone].present?
        retry_input = input.dup
        retry_input.delete(:phone)
        resp2 = @client.query(q, variables: { "input" => retry_input.stringify_keys })
        out = summarize_mutation(resp2, "customerCreate")
      end
      out
    end

    def run_customer_update(input)
      id = input[:id]
      if id.blank? || input.except(:id).blank?
        return { ok: false, skipped: true, reason: "nothing_to_update", customer_id: id, user_errors: [], graphql_errors: [] }
      end

      q = @client.parse(<<~GRAPHQL)
        mutation ($input: CustomerInput!) {
          customerUpdate(input: $input) {
            customer {
              id
            }
            userErrors {
              field
              message
            }
          }
        }
      GRAPHQL
      resp = @client.query(q, variables: { "input" => input.stringify_keys })
      out = summarize_mutation(resp, "customerUpdate")
      if out[:user_errors].any? { |m| m.to_s.downcase.include?("phone has already been taken") } && input[:phone].present?
        retry_input = input.dup
        retry_input.delete(:phone)
        resp2 = @client.query(q, variables: { "input" => retry_input.stringify_keys })
        out = summarize_mutation(resp2, "customerUpdate")
      end
      out
    end

    def summarize_mutation(resp, mutation_name)
      top = graphql_top_level_errors(resp)
      field = mutation_name.to_s.underscore.to_sym
      payload = resp&.data&.public_send(field) if resp&.data&.respond_to?(field)
      payload_nil = payload.nil?
      user_errors =
        if payload&.user_errors.present?
          payload.user_errors.map { |e| e.try(:message) || e.to_s }
        else
          []
        end
      customer_id = payload&.customer&.id
      ok = top.empty? && user_errors.empty? && payload.present? && customer_id.present?

      if user_errors.present?
        Rails.logger.warn "[FormsCustomerSyncService] shop_id=#{@shop.id} #{mutation_name} userErrors=#{user_errors.join('; ')}"
      end
      if payload_nil && top.present?
        Rails.logger.warn "[FormsCustomerSyncService] shop_id=#{@shop.id} #{mutation_name} graphqlErrors=#{top.join('; ')}"
      end
      if payload_nil && top.blank?
        # Rare but important: Shopify returned { data: { mutation: null } } with no top-level errors.
        # Log the raw hash so we can see extensions / permissions messages.
        raw = resp.respond_to?(:original_hash) ? resp.original_hash : nil
        Rails.logger.warn "[FormsCustomerSyncService] shop_id=#{@shop.id} #{mutation_name} returned null payload (raw_errors=#{raw&.dig('errors')}, raw_data_present=#{raw&.key?('data')})"
      end

      {
        ok: ok,
        skipped: false,
        customer_id: customer_id,
        user_errors: user_errors,
        graphql_errors: top
      }
    end
  end
end
