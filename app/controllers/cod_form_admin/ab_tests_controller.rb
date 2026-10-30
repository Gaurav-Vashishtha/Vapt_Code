# frozen_string_literal: true

module CodFormAdmin
  # A/B tests on offers (D.15, B.6, OFF-12). Gate `ab_tests`. Variants are locked once started.
  class AbTestsController < BaseController
    RESULT_EVENTS = { "cf_offer_view" => "views", "cf_upsell_view" => "views", "cf_downsell_shown" => "views",
                      "cf_offer_accept" => "accepts", "cf_upsell_accept" => "accepts", "cf_downsell_accept" => "accepts",
                      "cf_order_created" => "orders" }.freeze

    before_action :load_test, only: %i[show update destroy start stop]

    def index
      tests, meta = paginate(scope.order(created_at: :desc, id: :desc))
      render json: { "items" => tests.map { |test| test_json(test) }, "meta" => meta }
    end

    # GET /cod_form/ab_tests/:id — with "results": [{"key","views","accepts","orders","revenue_cents"}]
    def show
      render json: test_json(@test).merge("results" => results(@test))
    end

    def create
      gate!("ab_tests")
      attrs = validated!(Validators::AbTest.normalize(body))
      check_variant_offers!(attrs)
      test = CodForm::AbTest.create!(attrs.merge("shop_id" => @shop.id, "status" => CodForm::AbTest::STATUS_DRAFT))
      audit("ab_test.#{test.id}.created", "", test.name)
      render json: test_json(test), status: :created
    end

    # PUT is rejected with 422 once the test has started.
    def update
      gate!("ab_tests")
      invalid!("base", "a test cannot be changed after it has started") if @test.started_at.present?

      old = test_json(@test)
      attrs = validated!(Validators::AbTest.normalize(body, current: old.slice("name", "offer_type", "variants")))
      check_variant_offers!(attrs)
      @test.update!(attrs)
      audit_changes("ab_test.#{@test.id}", old.slice("name", "offer_type", "variants"), attrs)
      render json: test_json(@test)
    end

    def destroy
      invalid!("base", "stop the test before deleting it") if @test.running?

      @test.destroy!
      audit("ab_test.#{@test.id}.deleted", @test.name, "")
      head :no_content
    end

    # POST /cod_form/ab_tests/:id/start
    def start
      gate!("ab_tests")
      invalid!("base", "the test is already running") if @test.running?
      invalid!("base", "a stopped test cannot be restarted; create a new one") if @test.stopped_at.present?

      offer_ids = check_variant_offers!("offer_type" => @test.offer_type, "variants" => @test.variants)
      taken = offer_scope.where(id: offer_ids).where.not(ab_test_id: [nil, @test.id]).exists?
      invalid!("variants", "an offer is already part of another running test") if taken

      CodForm::AbTest.transaction do
        @test.start!
        offer_scope.where(id: offer_ids).update_all(ab_test_id: @test.id, updated_at: Time.current)
      end
      audit("ab_test.#{@test.id}.status", "draft", "running")
      bump!
      render json: test_json(@test)
    end

    # POST /cod_form/ab_tests/:id/stop  {"winner_key": "a"} (optional)
    def stop
      invalid!("base", "the test is not running") unless @test.running?

      winner = body["winner_key"].presence
      invalid!("winner_key", "is not one of the variant keys") if winner && !@test.variant_keys.include?(winner)

      CodForm::AbTest.transaction do
        @test.stop!(winner_key: winner)
        offer_scope.where(ab_test_id: @test.id).update_all(ab_test_id: nil, updated_at: Time.current)
      end
      audit("ab_test.#{@test.id}.status", "running", "stopped")
      bump!
      render json: test_json(@test).merge("results" => results(@test))
    end

    private

    def scope
      CodForm::AbTest.where(shop_id: @shop.id)
    end

    def offer_scope
      CodForm::Offer.where(shop_id: @shop.id)
    end

    def load_test
      @test = scope.find(params[:id])
    end

    def test_json(test)
      {
        "id" => test.id, "name" => test.name, "offer_type" => test.offer_type, "status" => test.status,
        "variants" => test.variants, "started_at" => iso(test.started_at), "stopped_at" => iso(test.stopped_at),
        "winner_key" => test.winner_key, "created_at" => iso(test.created_at)
      }
    end

    # Every variant offer must be an offer of this shop with the test's offer type. Returns the ids.
    def check_variant_offers!(attrs)
      ids = Array(attrs["variants"]).filter_map { |variant| variant["offer_id"] }
      invalid!("variants", "each variant needs a different offer") if ids.uniq.size != ids.size

      found = offer_scope.where(id: ids, offer_type: attrs["offer_type"])
                         .where.not(status: CodForm::Offer::STATUS_ARCHIVED).count
      invalid!("variants", "every offer must exist and be of type #{attrs['offer_type']}") if found != ids.size
      ids
    end

    # Per-variant counts from the funnel events of the test's run (metadata.ab = {"<test id>": "<key>"},
    # I.1). Test sessions are excluded. Raw events are kept for 90 days.
    def results(test)
      base = test.variant_keys.each_with_object({}) do |key, out|
        out[key] = { "key" => key, "views" => 0, "accepts" => 0, "orders" => 0, "revenue_cents" => 0 }
      end
      return base.values if test.started_at.nil?

      variant = Arel.sql("metadata -> 'ab' ->> #{FormFunnelEvent.connection.quote(test.id.to_s)}")
      events = FormFunnelEvent.where(shop_id: @shop.id, event_type: RESULT_EVENTS.keys)
                              .where("occurred_at >= ?", test.started_at)
                              .where("jsonb_exists(metadata -> 'ab', :id)", id: test.id.to_s)
                              .where("COALESCE(metadata ->> 'test', 'false') <> 'true'")
      events = events.where("occurred_at <= ?", test.stopped_at) if test.stopped_at

      events.group(variant, :event_type).count.each do |(key, event_type), count|
        row = base[key]
        row[RESULT_EVENTS.fetch(event_type)] += count if row
      end
      events.where(event_type: "cf_order_created").group(variant)
            .sum(Arel.sql("COALESCE(NULLIF(metadata ->> 'value_cents', '')::bigint, 0)")).each do |key, cents|
        base[key]["revenue_cents"] = cents.to_i if base[key]
      end
      base.values
    rescue StandardError => e
      Rails.logger.warn("[CodFormAdmin::AbTestsController] results unavailable shop_id=#{@shop.id} #{e.class}")
      base ? base.values : []
    end
  end
end
