module TwilioHelper
  def build_twiml(lang, intro, confirm, cancel, webhook_path = '/twillio/test_ivr_webhook')
    # lang = :hi
    if not lang
      lang = :en
    end
    voice_map = {
      en: 'alice',
      de: 'Polly.Hans',
      es: 'Polly.Conchita',
      it: 'Polly.Carla',
      hi: 'Polly.Aditi',
      fr: 'Polly.Chantal'
    }
    request = Twilio::TwiML::VoiceResponse.new do |r|
      2.times {
        r.gather(
          action: "https://#{ENV['APP_HOST']}#{webhook_path}",
          numDigits: '1',
          method: 'POST'
        ) do |g|
          g.say(
            message: intro,
            language: lang,
            voice: voice_map[lang] || voice_map[:en],
          )
          g.pause(length: 1)
          g.say(
            message: confirm,
            language: lang,
            voice: voice_map[lang] || voice_map[:en],
          )
          g.pause(length: 1)
          g.say(
            message: cancel,
            language: lang,
            voice: voice_map[lang] || voice_map[:en],
          )
          g.pause(length: 1)
        end
      }
      # r.redirect(gather.to_xml)
      # r.say(
      #   message: message,
      #   language: lang,
      #   voice: voice_map[lang] || voice_map[:en],
      #   loop: 2
      # )
    end
    return request.to_s
  end
end
