require 'test_helper'

class Whatsapp::OrderProductImageResolverTest < ActiveSupport::TestCase
  R = Whatsapp::OrderProductImageResolver

  test 'jpg/png/jpeg are supported and deliverable' do
    %w[
      https://cdn.shopify.com/x/a.jpg
      https://cdn.shopify.com/x/a.jpeg
      https://cdn.shopify.com/x/a.PNG
      https://cdn.shopify.com/x/a.png?v=123
    ].each do |u|
      assert R.supported_image_url?(u), u
      assert R.deliverable_image_url?(u), u
      refute R.convertible_image_url?(u), u
    end
  end

  test 'heic/heif/webp are convertible and deliverable but not natively supported' do
    %w[
      https://cdn.shopify.com/x/IMG_8012.heic?v=1771345984
      https://cdn.shopify.com/x/a.HEIF
      https://cdn.shopify.com/x/a.webp
    ].each do |u|
      refute R.supported_image_url?(u), u
      assert R.convertible_image_url?(u), u
      assert R.deliverable_image_url?(u), u
    end
  end

  test 'svg/gif and non-http values are neither supported nor convertible' do
    ['https://cdn.shopify.com/x/a.svg', 'https://cdn.shopify.com/x/a.gif', '/relative/a.jpg', nil, ''].each do |u|
      refute R.supported_image_url?(u), u.inspect
      refute R.convertible_image_url?(u), u.inspect
      refute R.deliverable_image_url?(u), u.inspect
    end
  end

  test 'a JPG line-item image is preferred over a HEIC one' do
    li = { 'image' => { 'src' => 'https://cdn.shopify.com/x/photo.heic' },
           'variant' => { 'image' => { 'src' => 'https://cdn.shopify.com/x/photo.jpg' } } }
    assert_equal 'https://cdn.shopify.com/x/photo.jpg', R.url_from_line_item(li)
  end

  test 'a HEIC line-item image is returned when it is the only option' do
    li = { 'image' => { 'src' => 'https://cdn.shopify.com/x/photo.heic?v=1' } }
    assert_equal 'https://cdn.shopify.com/x/photo.heic?v=1', R.url_from_line_item(li)
  end

  test 'abandoned_cart resolves the HEIC checkout image from the payload without a Shopify call' do
    payload = {
      'checkout' => {
        'line_items' => [
          { 'image' => { 'src' => 'https://cdn.shopify.com/s/files/1/0714/7175/9598/files/IMG_8012.heic?v=1771345984' },
            'product_id' => '9249772044526' }
        ]
      }
    }
    url = R.call(payload: payload, event_type_key: 'abandoned_cart', shop: nil)
    assert_equal 'https://cdn.shopify.com/s/files/1/0714/7175/9598/files/IMG_8012.heic?v=1771345984', url
  end
end
