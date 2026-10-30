# frozen_string_literal: true

class CallReminder < ApplicationRecord
  STATUSES = %w[open done cancelled].freeze

  # Which team owns the callback. Legacy rows have team = NULL and are treated
  # as "support" (the default), so #for_team("support") includes them.
  TEAMS = %w[support sales].freeze
  DEFAULT_TEAM = "support"

  scope :open_reminders, -> { where(status: "open") }
  scope :due_by, ->(date) { open_reminders.where("due_on <= ?", date) }
  scope :for_month, ->(start_date, end_date) { open_reminders.where(due_on: start_date..end_date) }
  scope :for_team, ->(team) {
    if team.to_s == "sales"
      where(team: "sales")
    else
      where("team IS NULL OR team = ?", "support")
    end
  }

  def self.normalize_team(value)
    TEAMS.include?(value.to_s) ? value.to_s : DEFAULT_TEAM
  end

  def self.open_domains_due_by(date)
    due_by(date).distinct.pluck(:shopify_domain)
  end

  def team_label
    (team.presence || DEFAULT_TEAM).capitalize
  end
end
