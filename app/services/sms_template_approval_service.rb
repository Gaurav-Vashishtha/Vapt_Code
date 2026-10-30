class SmsTemplateApprovalService
  Result = Struct.new(:ok?, :record, :errors, keyword_init: true)

  def self.submit(shop:, template_type_key:, body:, submitted_by:)
    new.submit(
      shop: shop,
      template_type_key: template_type_key,
      body: body,
      submitted_by: submitted_by
    )
  end

  def self.review(approval:, status:, reviewed_by:, reason:)
    new.review(approval: approval, status: status, reviewed_by: reviewed_by, reason: reason)
  end

  def submit(shop:, template_type_key:, body:, submitted_by:)
    config = SmsTemplateTypeConfig.active.find_by(key: template_type_key)
    return Result.new(ok?: false, errors: ["Invalid template type"]) unless config

    unless shop&.setting
      return Result.new(ok?: false, errors: ["Shop settings not found"])
    end

    if SmsTemplateApproval.where(
      shop_id: shop.id,
      template_type_key: config.key,
      status: SmsTemplateApproval::STATUSES[:pending]
    ).exists?
      return Result.new(
        ok?: false,
        errors: ["A template request for this type is already pending approval. Please wait for review before submitting another."]
      )
    end

    validation = SmsTemplateVariableValidator.call(body: body, type_config: config)
    return Result.new(ok?: false, errors: validation.errors) unless validation.ok?

    approval = SmsTemplateApproval.create(
      shop: shop,
      setting: shop.setting,
      template_type_key: config.key,
      target_column: config.target_column,
      body: body.to_s.strip,
      variables_used: validation.variables,
      max_variables: config.max_variables,
      status: SmsTemplateApproval::STATUSES[:pending],
      submitted_by: submitted_by,
      submitted_at: Time.current
    )

    if approval.persisted?
      notify_template_submission(approval)
      Result.new(ok?: true, record: approval, errors: [])
    else
      Result.new(ok?: false, record: approval, errors: approval.errors.full_messages)
    end
  end

  def review(approval:, status:, reviewed_by:, reason:)
    new_status = status.to_s
    unless [SmsTemplateApproval::STATUSES[:approved], SmsTemplateApproval::STATUSES[:rejected]].include?(new_status)
      return Result.new(ok?: false, record: approval, errors: ["Invalid review status"])
    end

    return Result.new(ok?: false, record: approval, errors: ["Only pending templates can be reviewed"]) unless approval.status == SmsTemplateApproval::STATUSES[:pending]

    ActiveRecord::Base.transaction do
      approval.update!(
        status: new_status,
        reviewed_by: reviewed_by,
        reviewed_at: Time.current,
        review_reason: reason
      )

      if new_status == SmsTemplateApproval::STATUSES[:approved]
        apply_to_settings!(approval)
      end
    end

    Result.new(ok?: true, record: approval, errors: [])
  rescue StandardError => e
    Result.new(ok?: false, record: approval, errors: [e.message])
  end

  private

  def apply_to_settings!(approval)
    setting = approval.setting
    column = approval.target_column.to_s

    unless setting.respond_to?(column)
      raise "Invalid settings column mapping: #{column}"
    end

    setting.update!(column => approval.body)
    approval.update!(applied_to_settings_at: Time.current)
  end

  def notify_template_submission(approval)
    WelcomeMailer.sms_template_submission_owner(approval.id).deliver_later
    WelcomeMailer.sms_template_submission_admin(approval.id).deliver_later
  rescue StandardError => e
    Rails.logger.warn("[SmsTemplateApprovalService] Failed to enqueue submission emails for approval #{approval.id}: #{e.message}")
  end
end
