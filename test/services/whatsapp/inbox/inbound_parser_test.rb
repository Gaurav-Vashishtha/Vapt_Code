# frozen_string_literal: true

require 'test_helper'

class Whatsapp::Inbox::InboundParserTest < ActiveSupport::TestCase
  SAMPLES = JSON.parse(File.read(Rails.root.join('test/fixtures/files/meta_inbound_samples.json')))

  SAMPLES.each do |name, sample|
    test "parses #{name}" do
      expect = sample['expect']
      parsed = Whatsapp::Inbox::InboundParser.parse(sample['message'])

      assert_equal expect['kind'], parsed[:kind]
      expect.key?('body') && expect['body'].nil? ? assert_nil(parsed[:body]) : assert_equal(expect['body'], parsed[:body])
      assert_equal expect['counts_for_window'], parsed[:counts_for_window]
      assert_includes WhatsappConversationMessage::KINDS, parsed[:kind]
      assert_equal expect['media_id'], parsed.dig(:media, :id) if expect.key?('media_id')
      assert_equal expect['file_name'], parsed.dig(:media, :file_name) if expect.key?('file_name')
      assert_equal expect['reply_to'], parsed[:reply_to_meta_message_id] if expect.key?('reply_to')
      Hash(expect['content']).each do |key, value|
        if value.is_a?(Hash)
          value.each { |k, v| assert_equal v, parsed[:content].dig(key, k), "content.#{key}.#{k}" }
        else
          assert_equal value, parsed[:content][key], "content.#{key}"
        end
      end
    end
  end

  test 'media without an id carries no media hash' do
    parsed = Whatsapp::Inbox::InboundParser.parse('type' => 'image', 'image' => { 'caption' => 'x' })
    assert_nil parsed[:media]
  end

  test 'unknown types are unsupported and keep the meta type' do
    parsed = Whatsapp::Inbox::InboundParser.parse('type' => 'poll', 'poll' => {})
    assert_equal 'unsupported', parsed[:kind]
    assert_equal 'poll', parsed[:content]['meta_type']
  end
end
