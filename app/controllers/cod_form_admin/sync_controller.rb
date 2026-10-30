# frozen_string_literal: true

module CodFormAdmin
  # Is everything the merchant saved live on the storefront, and a way to make it so.
  #
  # Two things can be saved but not live:
  #   * storefront settings (buttons, visibility, offers on the product page): they travel in the
  #     `codk.cod_form` shop metafield, written by a background job after every save;
  #   * a form whose draft was saved in the designer but not published.
  # Every COD Form screen shows the same "not published" bar from this, with one Publish action.
  class SyncController < BaseController
    # GET /cod_form/sync
    def show
      render json: sync_json
    end

    # POST /cod_form/sync — publishes the saved form drafts, then writes the metafield, now.
    def create
      form_errors = draft_forms.filter_map do |form|
        form.publish!
        nil
      rescue ActiveRecord::RecordInvalid
        { "id" => form.id, "name" => form.name.to_s }
      end
      result = publish_storefront!
      @config.reload
      render json: sync_json.merge("status" => result[:status].to_s, "form_errors" => form_errors)
    end

    private

    def draft_forms
      CodForm::Form.where(shop_id: @shop.id).active.ordered.select(&:unpublished_changes?)
    end

    def sync_json
      drafts = draft_forms
      forms = drafts.map { |form| { "id" => form.id, "name" => form.name.to_s } }
      pending = @config.metafield_stale?
      {
        "live" => !pending && forms.empty?,
        "pending" => pending,
        "forms" => forms,
        # Changes with every save that is still waiting, so the screen can tell a new one.
        "stamp" => ([@config.config_version] + drafts.map { |form| form.updated_at.to_i }).join("-"),
        "config_version" => @config.config_version,
        "synced_version" => @config.metafield_synced_version,
        "synced_at" => @config.metafield_synced_at&.iso8601
      }
    end
  end
end
