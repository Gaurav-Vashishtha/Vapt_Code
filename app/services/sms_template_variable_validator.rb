class SmsTemplateVariableValidator
  TOKEN_REGEX = /\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/.freeze
  HARD_MAX_VARIABLES = 3
  VARIABLE_RENDER_LENGTH = 15
  MAX_SMS_LENGTH = 160

  Result = Struct.new(:ok?, :variables, :variable_count, :errors, keyword_init: true)

  def self.call(body:, type_config:)
    new(body: body, type_config: type_config).call
  end

  def initialize(body:, type_config:)
    @body = body.to_s
    @type_config = type_config
  end

  def call
    variable_tokens = extract_variable_tokens
    variables = variable_tokens.uniq
    errors = []

    allowed = normalize_allowed_variables(@type_config.allowed_variables)
    disallowed = variables - allowed
    if disallowed.any?
      errors << "Unsupported variables: #{disallowed.join(', ')}"
    end

    max_variables = [@type_config.max_variables.to_i, HARD_MAX_VARIABLES].reject(&:zero?).min || HARD_MAX_VARIABLES
    if max_variables.positive? && variable_tokens.size > max_variables
      errors << "Variable count #{variable_tokens.size} exceeds allowed limit #{max_variables}"
    end

    simulated_length = simulated_rendered_length
    if simulated_length > MAX_SMS_LENGTH
      errors << "Template is too long. Estimated SMS length #{simulated_length} exceeds #{MAX_SMS_LENGTH} (variables assumed #{VARIABLE_RENDER_LENGTH} chars each)"
    end

    Result.new(ok?: errors.empty?, variables: variables, variable_count: variable_tokens.size, errors: errors)
  end

  private

  def extract_variable_tokens
    @body.scan(TOKEN_REGEX).flatten.map(&:to_s)
  end

  def simulated_rendered_length
    @body.gsub(TOKEN_REGEX, "x" * VARIABLE_RENDER_LENGTH).length
  end

  def normalize_allowed_variables(value)
    case value
    when Array
      value.map { |v| v.to_s.strip }.reject(&:empty?)
    when String
      str = value.strip
      begin
        parsed = JSON.parse(str)
        return parsed.map { |v| v.to_s.strip }.reject(&:empty?) if parsed.is_a?(Array)
      rescue JSON::ParserError
        # Fallback to custom formats below
      end

      str = str.gsub(/^\[/, "").gsub(/\]$/, "")
      str.split(",").map { |v| v.to_s.strip.gsub(/\A['"]|['"]\z/, "") }.reject(&:empty?)
    when Hash
      value.values.map { |v| v.to_s.strip }.reject(&:empty?)
    else
      []
    end
  end
end
