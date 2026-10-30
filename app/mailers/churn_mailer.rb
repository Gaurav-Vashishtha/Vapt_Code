class ChurnMailer < ApplicationMailer
  layout 'mailer'

  def weekly_digest(recipients, data)
    @data = data
    @kpis = data[:kpis] || {}
    @reasons = data[:reasons] || []
    @cohorts = data[:cohorts] || []
    @worklist = data[:worklist] || []
    mail(to: recipients, subject: "COD King — Weekly Churn Digest (#{Date.current.strftime('%d %b %Y')})")
  end

  def win_back(email, trigger:, domain:, owner:)
    @trigger = trigger
    @domain = domain
    @owner = owner.presence || 'there'
    subject = trigger == 'just_churned' ? 'We’d love to have you back on COD King' : 'Need a hand getting the most out of COD King?'
    mail(to: email, subject: subject)
  end
end
