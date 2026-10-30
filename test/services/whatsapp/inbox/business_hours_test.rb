# frozen_string_literal: true

require 'test_helper'

class Whatsapp::Inbox::BusinessHoursTest < ActiveSupport::TestCase
  KOLKATA = ActiveSupport::TimeZone['Asia/Kolkata']

  def setting(hours)
    WhatsappInboxSetting.new(business_hours: hours)
  end

  def weekdays_9_to_6
    WhatsappInboxSetting::DAYS.index_with { |d| %w[sat sun].include?(d) ? [] : [%w[09:00 18:00]] }
  end

  test 'empty hours means always open' do
    assert Whatsapp::Inbox::BusinessHours.open?(setting({}), Time.utc(2026, 10, 18, 2, 0), zone: KOLKATA)
  end

  test 'uses the store timezone, not UTC' do
    s = setting(weekdays_9_to_6)
    monday_10am_ist = KOLKATA.local(2026, 10, 19, 10, 0)
    monday_7pm_ist = KOLKATA.local(2026, 10, 19, 19, 0)

    assert Whatsapp::Inbox::BusinessHours.open?(s, monday_10am_ist.utc, zone: KOLKATA)
    assert Whatsapp::Inbox::BusinessHours.closed?(s, monday_7pm_ist.utc, zone: KOLKATA)
    assert Whatsapp::Inbox::BusinessHours.closed?(s, Time.utc(2026, 10, 19, 4, 0), zone: ActiveSupport::TimeZone['UTC'])
  end

  test 'closing time is exclusive and closed days stay closed' do
    s = setting(weekdays_9_to_6)
    assert Whatsapp::Inbox::BusinessHours.closed?(s, KOLKATA.local(2026, 10, 19, 18, 0), zone: KOLKATA)
    assert Whatsapp::Inbox::BusinessHours.open?(s, KOLKATA.local(2026, 10, 19, 17, 59), zone: KOLKATA)
    assert Whatsapp::Inbox::BusinessHours.closed?(s, KOLKATA.local(2026, 10, 18, 12, 0), zone: KOLKATA)
  end

  test 'supports several ranges in a day' do
    hours = weekdays_9_to_6.merge('mon' => [%w[09:00 13:00], %w[14:00 18:00]])
    s = setting(hours)
    assert Whatsapp::Inbox::BusinessHours.closed?(s, KOLKATA.local(2026, 10, 19, 13, 30), zone: KOLKATA)
    assert Whatsapp::Inbox::BusinessHours.open?(s, KOLKATA.local(2026, 10, 19, 14, 30), zone: KOLKATA)
  end

  test 'settings reject malformed hours' do
    s = WhatsappInboxSetting.new(business_hours: { 'mon' => [%w[18:00 09:00]] }, unanswered_email_minutes: 30)
    assert_not s.valid?
    assert s.errors[:business_hours].any?
  end
end
