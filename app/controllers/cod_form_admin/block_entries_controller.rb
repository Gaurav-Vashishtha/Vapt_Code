# frozen_string_literal: true

module CodFormAdmin
  # Block lists for phone, email and IP (D.15, C.5, FRD-1). Gate `block_lists`.
  # Limit: 5 000 entries per kind per shop; 5 000 values per request.
  # Entry values are buyer data: they are never logged and never written to the audit trail
  # (the audit records counts only).
  class BlockEntriesController < BaseController
    # GET /cod_form/block_entries?kind=phone&q=&page=1
    def index
      list = scope
      list = list.of_kind(params[:kind]) if params[:kind].present?
      query = params[:q].to_s.strip
      if query.present?
        like = "%#{CodForm::BlockEntry.sanitize_sql_like(query.downcase)}%"
        list = list.where("LOWER(value) LIKE :like OR value_normalized LIKE :like", like: like)
      end
      entries, meta = paginate(list.order(created_at: :desc, id: :desc))
      render json: { "items" => entries.map { |entry| entry_json(entry) }, "meta" => meta }
    end

    # POST /cod_form/block_entries
    #   {"kind", "value", "note"}        one entry (422 when invalid or already listed)
    #   {"kind", "values": ["…", …]}     bulk: invalid, duplicate and over-limit values are skipped
    # → {"created": n, "skipped": n}
    def create
      gate!("block_lists")
      kind = body["kind"].to_s
      bulk = body.key?("values")
      values = bulk ? body["values"] : [body["value"]]
      note_errors = Validators::Util.errors
      note = Validators::Util.string(body["note"], "note", note_errors, "", max: 255)
      raise ValidationError.new(note_errors.reject { |_, list| list.empty? }) if note_errors.any? { |_, list| list.any? }

      existing = scope.of_kind(kind).pluck(:value_normalized)
      prepared = Validators::BlockEntries.prepare(kind: kind, values: values, existing: existing)
      raise ValidationError.new(prepared["errors"]) if prepared["errors"].any?

      unless bulk
        invalid!("value", "is not a valid #{kind} entry") if prepared["invalid"].positive?
        invalid!("base", "limit reached: at most #{Validators::BlockEntries::MAX_PER_KIND} #{kind} entries") if prepared["over_limit"].positive?
        invalid!("value", "is already on the list") if prepared["entries"].empty?
      end

      created = insert(kind, prepared["entries"], note.presence, bulk)
      audit("block_entries.#{kind}.count", existing.size, existing.size + created) if created.positive?
      render json: { "created" => created, "skipped" => prepared["skipped"] + (prepared["entries"].size - created),
                     "invalid" => prepared["invalid"], "over_limit" => prepared["over_limit"] }
    end

    def destroy
      entry = scope.find(params[:id])
      before = scope.of_kind(entry.kind).count
      entry.destroy!
      audit("block_entries.#{entry.kind}.count", before, before - 1)
      head :no_content
    end

    private

    def scope
      CodForm::BlockEntry.where(shop_id: @shop.id)
    end

    # One INSERT; rows that lose a race against the unique index are skipped by the database.
    def insert(kind, entries, note, bulk)
      return 0 if entries.empty?

      now = Time.current
      created_by = bulk && entries.size > 1 ? "import" : (@shop.owner_email.presence || "merchant")
      rows = entries.map do |entry|
        { shop_id: @shop.id, kind: kind, value: entry["value"], value_normalized: entry["value_normalized"],
          note: note, created_by: created_by, created_at: now, updated_at: now }
      end
      CodForm::BlockEntry.insert_all(rows, unique_by: %i[shop_id kind value_normalized]).length
    end

    def entry_json(entry)
      { "id" => entry.id, "kind" => entry.kind, "value" => entry.value, "value_normalized" => entry.value_normalized,
        "note" => entry.note, "created_by" => entry.created_by, "created_at" => iso(entry.created_at) }
    end
  end
end
