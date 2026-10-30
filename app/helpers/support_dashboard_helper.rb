# frozen_string_literal: true

module SupportDashboardHelper
  def support_core_tab_class(active, tab)
    base = "py-4 px-1 border-b-2 font-medium text-sm "
    if active.to_sym == tab.to_sym
      "#{base}border-blue-500 text-blue-600"
    else
      "#{base}border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300"
    end
  end

  # Where the follow-up column's "add" forms post: live shops use the shop
  # route, uninstall snapshots use the uninstalled-shop route.
  def follow_up_create_path(owner)
    if owner.is_a?(UninstalledShop)
      support_dashboard_create_uninstalled_follow_up_path(owner)
    else
      support_dashboard_follow_ups_path(owner)
    end
  end

  # Builds a normalized list of follow-up entries to render in the follow-up column partial.
  # Returns an array of hashes with keys used by `_follow_up_column.html.erb`.
  def follow_up_entries(shop, source_tab)
    return [] unless shop.present?

    follow_ups =
      shop
        .follow_ups
        .includes(:follow_up_comments)
        .where(source_tab: source_tab.to_s)
        .order(created_at: :desc)

    follow_ups.map do |fu|
      {
        follow_up_id: fu.id,
        status: fu.status.to_sym,
        notes: fu.notes.to_s,
        created_at: fu.created_at,
        resolved_at: fu.resolved_at,
        resolved_notes: fu.resolved_notes.to_s,
        created_by: parse_bracket_prefix(fu.notes),
        resolved_by: parse_bracket_prefix(fu.resolved_notes).presence || fu.resolved_by
      }
    end
  end

  def follow_up_entry_header(entry)
    ts =
      if entry[:status] == :resolved
        entry[:resolved_at] || entry[:created_at]
      else
        entry[:created_at]
      end

    who =
      if entry[:status] == :resolved
        entry[:resolved_by].presence
      else
        entry[:created_by].presence
      end

    parts = []
    parts << (ts.present? ? ts.strftime("%b %d, %Y") : "Unknown date")
    parts << who if who.present?
    parts.join(" • ")
  end

  def follow_up_entry_body(entry)
    body =
      if entry[:status] == :resolved
        entry[:resolved_notes].presence || entry[:notes].to_s
      else
        entry[:notes].to_s
      end

    strip_bracket_prefix(body)
  end

  def follow_up_status_badge_classes(entry)
    case entry[:status].to_sym
    when :pending
      "bg-yellow-100 text-yellow-800"
    when :resolved
      "bg-green-100 text-green-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  private

  def parse_bracket_prefix(text)
    match = text.to_s.match(/\A\[(?<name>[^\]]+)\]\s+/)
    match ? match[:name].to_s.strip : nil
  end

  def strip_bracket_prefix(text)
    text.to_s.sub(/\A\[[^\]]+\]\s+/, "")
  end
end
