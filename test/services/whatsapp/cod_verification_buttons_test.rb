require 'test_helper'

class Whatsapp::CodVerificationButtonsTest < ActiveSupport::TestCase
  M = Whatsapp::CodVerificationButtons

  def components(*buttons)
    [{ 'type' => 'BODY', 'text' => 'Confirm your order' }, { 'type' => 'BUTTONS', 'buttons' => buttons }]
  end

  def qr(text)
    { 'type' => 'QUICK_REPLY', 'text' => text }
  end

  test 'maps payloads by label, not position' do
    assert_equal [{ 'index' => 0, 'payload' => 'cod_cancel' }, { 'index' => 1, 'payload' => 'cod_confirm' }],
                 M.payload_params(components(qr('Cancel order'), qr('Confirm order')))
  end

  test 'uses the real button index when a URL button comes first' do
    url = { 'type' => 'URL', 'text' => 'Track', 'url' => 'https://example.com' }
    assert_equal [{ 'index' => 1, 'payload' => 'cod_confirm' }, { 'index' => 2, 'payload' => 'cod_cancel' }],
                 M.payload_params(components(url, qr('Confirm'), qr('Cancel')))
  end

  test 'extra buttons get no payload' do
    assert_equal [{ 'index' => 0, 'payload' => 'cod_confirm' }, { 'index' => 2, 'payload' => 'cod_cancel' }],
                 M.payload_params(components(qr('Confirm'), qr('Change address'), qr('Cancel')))
    assert_nil M.payload_for_label(components(qr('Confirm'), qr('Change address'), qr('Cancel')), 'Change address')
  end

  test 'falls back to confirm-then-cancel for two unreadable labels' do
    assert_equal %w[cod_confirm cod_cancel],
                 M.payload_params(components(qr('ऑर्डर पक्का'), qr('वापस'))).map { |p| p['payload'] }
  end

  test 'mapping_error rejects templates without both a confirm and a cancel button' do
    assert_nil M.mapping_error(components(qr('Cancel'), qr('Confirm')))
    assert M.mapping_error(components(qr('Confirm'), qr('Change address')))
    assert M.mapping_error(components(qr('Confirm')))
    assert M.mapping_error(components(qr('Confirm'), qr('Confirm now')))
  end
end
