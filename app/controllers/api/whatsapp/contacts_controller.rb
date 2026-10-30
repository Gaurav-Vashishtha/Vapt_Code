module Api
  module Whatsapp
    class ContactsController < AuthenticatedController
      PAGE_SIZE = 50

      def index
        scope = filtered_scope
        page = scope.order(updated_at: :desc).limit(PAGE_SIZE).offset(params[:offset].to_i)
        render json: { contacts: page.map { |c| serialize(c) }, total: scope.count, page_size: PAGE_SIZE }
      end

      def create
        phone = WhatsappContact.normalize_phone(params[:phone])
        return render_error('A valid phone number (with country code) is required.') if phone.blank?

        contact = WhatsappContact.find_or_initialize_by(shop_id: @shop.id, phone: phone)
        contact.source = 'manual' if contact.new_record?
        assign_editable(contact)
        if contact.save
          render json: { contact: serialize(contact) }, status: :created
        else
          render_error(contact.errors.full_messages.to_sentence)
        end
      end

      def update
        contact = find_contact or return
        assign_editable(contact)
        if contact.save
          render json: { contact: serialize(contact) }
        else
          render_error(contact.errors.full_messages.to_sentence)
        end
      end

      def destroy
        contact = find_contact or return
        contact.destroy
        head :no_content
      end

      def bulk_tag
        ids = Array(params[:ids]).map(&:to_i)
        return render_error('Select at least one contact.') if ids.empty?
        add = WhatsappContact.sanitize_tags(params[:add_tags])
        remove = WhatsappContact.sanitize_tags(params[:remove_tags])
        return render_error('Nothing to change.') if add.empty? && remove.empty?

        WhatsappContact.where(shop_id: @shop.id, id: ids).find_each do |c|
          c.update_columns(tags: ((Array(c.tags) + add).uniq - remove), updated_at: Time.current)
        end
        render json: { updated: ids.size }
      end

      def import
        content = params[:file].respond_to?(:read) ? params[:file].read : params[:raw_content].to_s
        return render_error('Upload a CSV file.') if content.blank?

        import = WhatsappAudienceImport.create!(shop_id: @shop.id, status: 'uploaded', raw_content: content)
        ::Whatsapp::ImportContactsJob.perform_async(import.id, WhatsappContact.sanitize_tags(params[:tags]))
        render json: { id: import.id, status: import.status }, status: :created
      end

      def sync
        if ::Whatsapp::SyncContactsJob.running?(@shop.id)
          return render json: { message: 'A sync is already running — hang on, contacts will appear as it finishes.',
                                sync: ::Whatsapp::SyncContactsJob.status(@shop.id) }
        end
        status = ::Whatsapp::SyncContactsJob.mark(@shop.id, status: 'queued', queued_at: Time.current.iso8601,
                                                         error: nil, carts: 0, customers: 0, upserted: 0)
        ::Whatsapp::SyncContactsJob.perform_async(@shop.id)
        render json: { message: 'Sync started. Contacts from your abandoned carts and Shopify customers will appear shortly.',
                       sync: status }
      end

      # Lightweight poll target while a sync is running.
      def sync_status
        render json: { sync: ::Whatsapp::SyncContactsJob.status(@shop.id) }
      end

      def meta
        base = WhatsappContact.where(shop_id: @shop.id)
        render json: {
          total: base.count,
          subscribed: base.subscribed.count,
          tags: WhatsappContact.tag_counts(@shop.id),
          attr_keys: WhatsappContact.attr_keys(@shop.id),
          sources: base.group(:source).count,
          sync: ::Whatsapp::SyncContactsJob.status(@shop.id)
        }
      end

      private

      def filtered_scope
        scope = WhatsappContact.where(shop_id: @shop.id)
        if params[:q].present?
          q = "%#{params[:q].to_s.strip}%"
          scope = scope.where('phone ILIKE :q OR name ILIKE :q OR first_name ILIKE :q OR last_name ILIKE :q OR email ILIKE :q', q: q)
        end
        if params[:tag].present?
          scope = scope.where('jsonb_exists_any(tags, ARRAY[?]::text[])', WhatsappContact.sanitize_tags(params[:tag]))
        end
        scope = scope.where(source: params[:source]) if params[:source].present?
        if params[:segment_id].present?
          segment = WhatsappSegment.find_by(id: params[:segment_id], shop_id: @shop.id)
          # Intersect with the segment's own scope so "contacts in this
          # segment" reuses SegmentQuery instead of re-implementing it.
          scope = segment ? scope.merge(segment.matching_scope) : scope.none
        end
        scope = scope.subscribed if params[:subscribed] == 'true'
        scope = scope.where(subscribed: false) if params[:subscribed] == 'false'
        scope
      end

      def assign_editable(contact)
        contact.name = params[:name].to_s.strip.presence if params.key?(:name)
        contact.first_name = params[:first_name].to_s.strip.presence if params.key?(:first_name)
        contact.last_name = params[:last_name].to_s.strip.presence if params.key?(:last_name)
        contact.email = params[:email].to_s.strip.presence if params.key?(:email)
        contact.tags = WhatsappContact.sanitize_tags(params[:tags]) if params.key?(:tags)
        contact.attrs = sanitize_attrs(params[:attrs]) if params.key?(:attrs)
        contact.subscribed = ActiveModel::Type::Boolean.new.cast(params[:subscribed]) != false if params.key?(:subscribed)
      end

      def sanitize_attrs(raw)
        (raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h)
          .transform_keys { |k| k.to_s.strip }
          .transform_values(&:to_s)
          .reject { |k, _| k.blank? }
          .first(50).to_h
      end

      def find_contact
        contact = WhatsappContact.find_by(id: params[:id], shop_id: @shop.id)
        render(json: { error: 'Contact not found' }, status: :not_found) unless contact
        contact
      end

      def render_error(msg)
        render json: { error: msg }, status: :unprocessable_entity
        nil
      end

      def serialize(c)
        { id: c.id, phone: c.phone, name: c.display_name, first_name: c.first_name,
          last_name: c.last_name, email: c.email, source: c.source, tags: Array(c.tags),
          attrs: c.attrs || {}, subscribed: c.subscribed, order_count: c.order_count,
          total_spent: c.total_spent, last_order_at: c.last_order_at, created_at: c.created_at }
      end
    end
  end
end
