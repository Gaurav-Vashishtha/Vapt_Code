require 'test_helper'

class CustomerSyncControlTest < ActiveSupport::TestCase
  teardown do
    CustomerSyncControl.resume!
  end

  test 'kill, pause and resume change the mode immediately' do
    CustomerSyncControl.kill!('test')
    assert CustomerSyncControl.killed?
    assert CustomerSyncControl.paused?

    CustomerSyncControl.pause!('test')
    assert_not CustomerSyncControl.killed?
    assert CustomerSyncControl.paused?

    CustomerSyncControl.resume!
    assert_not CustomerSyncControl.paused?
  end

  test 'a change made in the database is seen after the cache window' do
    CustomerSyncControl.resume!
    CustomerSyncControl.where(name: 'global').update_all(mode: 'killed')

    assert_equal 'killed', CustomerSyncControl.fresh_mode
  end

  test 'an unknown mode is rejected' do
    assert_raises(ArgumentError) { CustomerSyncControl.set!('stopped') }
  end

  test 'legacy pull jobs stay off unless explicitly enabled' do
    assert_not LegacyCustomerPull.enabled?
  end
end
