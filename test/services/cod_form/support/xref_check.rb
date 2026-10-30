# frozen_string_literal: true

# Static cross-reference check of the COD Form module (docs/cod-form/notes/integration.md, item 13).
# No Rails, no gems beyond the `prism` parser that ships with Ruby 3.3:
#
#   ruby test/services/cod_form/support/xref_check.rb          # exit 1 when something is wrong
#   ruby test/services/cod_form/support/xref_check.rb -v       # also lists every reference checked
#
# What it checks, over every Ruby file of the module:
#   1. constants   — every `CodForm::…`, `CodFormAdmin::…`, `Api::Form::…`, `Admin::CodForm::…`
#                    reference (also relative ones inside those namespaces) names a constant that a
#                    module file defines;
#   2. methods     — every `<module constant>.method(args)` call: the singleton method exists, is
#                    not private, and the call's positional / keyword arguments fit its signature;
#   3. Zeitwerk    — file path ⇄ constant name for every file under app/ (with the `collapse` of
#                    app/services/cod_form/adapters), and the guarded `require_relative` lines;
#   4. Sidekiq     — every perform_async / perform_in target is a job whose #perform accepts the
#                    arguments; every cron entry in config/schedule.yml names an existing class;
#   5. mailer      — every mailer action has a view; every i18n key the mailer and its views use
#                    exists in config/locales/en.yml;
#   6. routes      — every COD Form route in config/routes.rb points at an existing public action.
# It is a static approximation (no inheritance from gems, no metaprogramming): what it cannot
# decide it lists under "not checked" instead of guessing. `zeitwerk:check` and the Rails test
# run on a booted app remain the authority for loading.
Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require "prism"
require "yaml"
require "set"

ROOT = File.expand_path("../../../..", __dir__)
VERBOSE = ARGV.include?("-v")

MODULE_GLOBS = %w[
  app/models/cod_form/**/*.rb app/models/concerns/cod_form/**/*.rb
  app/services/cod_form/**/*.rb app/services/shopify_services/order_edit_add_line_service.rb
  app/workers/cod_form/**/*.rb
  app/controllers/api/form/**/*.rb app/controllers/cod_form_admin/**/*.rb app/controllers/admin/cod_form/**/*.rb
  app/dashboards/cod_form/**/*.rb app/fields/json_text_field.rb app/mailers/cod_form_mailer.rb
  lib/cod_form_shopify_timeout.rb
].freeze
# Existing files the module edited: scanned for references only.
REFERENCE_ONLY = %w[
  app/models/shop.rb app/models/form_funnel_event.rb app/models/abandoned_cart.rb
  app/controllers/api/cod_orders_controller.rb app/controllers/script_controller.rb
  app/services/shopify_services/cod_order_create_service.rb app/services/shopify_services/payment_customization_service.rb
  app/services/campaign_attribution_helper.rb app/workers/order_confirmation_create_job.rb
  config/initializers/cod_form.rb config/initializers/rack_attack.rb
].freeze
NAMESPACE_ROOTS = %w[CodForm CodFormAdmin Api::Form Admin::CodForm CodFormMailer CodFormShopifyTimeout JsonTextField].freeze
COLLAPSED = ["app/services/cod_form/adapters"].freeze

# Class methods a class gets from its framework superclass (never defined in the module's files).
AR_CLASS_METHODS = %i[
  where find find_by find_by! create create! new all first last exists? count pluck pick order joins includes
  update_all delete_all destroy_all find_each find_in_batches in_batches transaction connection insert_all upsert_all
  insert_all! find_or_create_by find_or_create_by! find_or_initialize_by first_or_create! first_or_create
  table_name quoted_table_name column_names columns_hash primary_key arel_table sanitize_sql_array sanitize_sql
  unscoped none limit select group distinct maximum minimum sum lock not reorder offset having ids
  filter_attributes model_name human_attribute_name reset_column_information attribute_names sanitize_sql_like
].to_set.freeze
JOB_CLASS_METHODS = %i[perform_async perform_in perform_at set sidekiq_options new perform_inline].to_set.freeze
ANY_CLASS_METHODS = %i[
  name to_s inspect respond_to? is_a? const_get const_defined? constants instance_method instance_methods method_defined?
  class_eval singleton_class send public_send freeze new ancestors include? prepend include extend allocate hash == === !=
  instance_variable_get instance_variable_set method methods superclass tap then
].to_set.freeze

Signature = Struct.new(:required, :optional, :rest, :key_required, :key_optional, :key_rest, :forwarding, keyword_init: true) do
  def self.any
    new(required: 0, optional: 0, rest: true, key_required: [], key_optional: [], key_rest: true, forwarding: false)
  end
end

ClassInfo = Struct.new(:name, :kind, :superclass, :file, :singleton, :private_singleton, :instance, :private_instance, :module_function, keyword_init: true)

$classes = {}          # full name => ClassInfo
$constants = Set.new   # full names of plain constants (FOO = ...), structs included
$references = []       # [file, line, nesting, const_text, method or nil, call node or nil]
$problems = []
$unchecked = []
$checked = Hash.new(0)

def problem(kind, message)
  $problems << "#{kind}: #{message}"
end

def rel(path)
  path.sub("#{ROOT}/", "")
end

def info_for(name, kind, superclass, file)
  $classes[name] ||= ClassInfo.new(name: name, kind: kind, superclass: superclass, file: file, singleton: {}, private_singleton: Set.new,
                                   instance: {}, private_instance: Set.new, module_function: false)
  info = $classes[name]
  info.superclass ||= superclass
  info.kind = kind if kind == :class
  info
end

def signature(def_node)
  params = def_node.parameters
  return Signature.new(required: 0, optional: 0, rest: false, key_required: [], key_optional: [], key_rest: false, forwarding: false) if params.nil?

  key_required = []
  key_optional = []
  params.keywords.each do |kw|
    name = kw.name.to_s.delete_suffix(":").to_sym
    required = kw.class.name.include?("Required") || (kw.respond_to?(:value) && kw.value.nil? && !kw.class.name.include?("Optional"))
    (required ? key_required : key_optional) << name
  end
  kw_rest = params.keyword_rest
  Signature.new(
    required: params.requireds.size + params.posts.size, optional: params.optionals.size, rest: !params.rest.nil?,
    key_required: key_required, key_optional: key_optional,
    key_rest: !kw_rest.nil? && kw_rest.class.name.include?("KeywordRest"),
    forwarding: !kw_rest.nil? && kw_rest.class.name.include?("Forwarding")
  )
end

def const_text(node)
  return nil if node.nil?
  return nil unless node.class.name.end_with?("ConstantReadNode", "ConstantPathNode")

  node.slice.gsub(/\s+/, "")
end

def symbol_args(call)
  return [] if call.arguments.nil?

  call.arguments.arguments.filter_map { |arg| arg.class.name.end_with?("SymbolNode") ? arg.unescaped.to_sym : nil }
end

# Walks one file: records definitions (when `define`) and every constant reference / call.
def walk(node, file, nesting, state, define)
  return if node.nil?

  type = node.class.name.split("::").last
  case type
  when "ModuleNode", "ClassNode"
    text = const_text(node.constant_path)
    full = text.start_with?("::") ? text[2..] : (nesting + [text]).join("::")
    superclass = type == "ClassNode" ? const_text(node.superclass)&.sub(/\A::/, "") : nil
    if define
      # Intermediate namespaces of `module A::B` and of the nesting exist too.
      parts = full.split("::")
      (1...parts.size).each { |i| info_for(parts.first(i).join("::"), :module, nil, file) }
      info_for(full, type == "ClassNode" ? :class : :module, superclass, file)
    end
    record_reference(node.superclass, file, nesting) if type == "ClassNode" && node.superclass
    inner = { visibility: :public, singleton: false, owner: full }
    walk(node.body, file, full.split("::"), inner, define)
    return
  when "SingletonClassNode"
    inner = { visibility: :public, singleton: true, owner: state[:owner] }
    walk(node.body, file, nesting, inner, define)
    return
  when "DefNode"
    if define && state[:owner]
      info = $classes[state[:owner]]
      singleton = state[:singleton] || !node.receiver.nil? || info.module_function
      sig = signature(node)
      if singleton
        info.singleton[node.name] = sig
        info.private_singleton << node.name if state[:visibility] == :private && node.receiver.nil? && state[:singleton]
        info.instance[node.name] = sig if info.module_function && !state[:singleton] && node.receiver.nil?
      else
        info.instance[node.name] = sig
        info.private_instance << node.name if state[:visibility] != :public
      end
    end
    walk(node.body, file, nesting, { visibility: :public, singleton: false, owner: nil, in_def: true }, false)
    return
  when "ConstantWriteNode"
    $constants << (nesting + [node.name.to_s]).join("::") if define
    # `Result = Struct.new(...)` / `Foo = Class.new` behave like classes with a free-form constructor.
    if define && node.value.class.name.end_with?("CallNode") && %i[new].include?(node.value.name)
      info = info_for((nesting + [node.name.to_s]).join("::"), :class, "Struct", file)
      info.singleton[:new] = Signature.any
    end
  when "CallNode"
    handle_call(node, file, nesting, state, define)
  when "ConstantPathNode", "ConstantReadNode"
    record_reference(node, file, nesting)
    return # do not descend: the parts of a path are not references of their own
  end

  node.compact_child_nodes.each { |child| walk(child, file, nesting, state, define) }
end

def handle_call(node, file, nesting, state, define)
  owner = state[:owner] && $classes[state[:owner]]
  if node.receiver.nil? && owner && define
    case node.name
    when :private, :protected
      if node.arguments.nil?
        state[:visibility] = :private
      else
        symbol_args(node).each { |name| state[:singleton] ? owner.private_singleton << name : owner.private_instance << name }
      end
    when :public
      state[:visibility] = :public if node.arguments.nil?
    when :private_class_method
      symbol_args(node).each { |name| owner.private_singleton << name }
    when :module_function
      owner.module_function = true if node.arguments.nil?
      symbol_args(node).each { |name| owner.singleton[name] ||= owner.instance[name] || Signature.any }
    when :scope
      symbol_args(node).first(1).each { |name| owner.singleton[name] = Signature.any }
    when :attr_reader, :attr_accessor, :attr_writer, :cattr_accessor, :mattr_accessor, :attribute, :delegate, :class_attribute
      symbol_args(node).each do |name|
        target = state[:singleton] || %i[cattr_accessor mattr_accessor attribute class_attribute].include?(node.name) ? owner.singleton : owner.instance
        target[name] = Signature.any
        target[:"#{name}="] = Signature.any
      end
    when :define_method
      symbol_args(node).first(1).each { |name| (state[:singleton] ? owner.singleton : owner.instance)[name] = Signature.any }
    when :alias_method
      names = symbol_args(node)
      (state[:singleton] ? owner.singleton : owner.instance)[names[0]] = Signature.any if names.size == 2
    end
  end

  text = const_text(node.receiver)
  $references << [file, node.location.start_line, nesting.dup, text, node.name, node] if text
end

def record_reference(node, file, nesting)
  text = const_text(node)
  $references << [file, node.location.start_line, nesting.dup, text, nil, nil] if text
end

# Lexical constant resolution against the module's own definitions.
# => full name, :external (not a module constant), or nil (looks like a module constant, undefined)
def resolve(text, nesting)
  absolute = text.start_with?("::")
  name = text.sub(/\A::/, "")
  candidates = absolute ? [name] : (nesting.size.downto(0).map { |i| (nesting.first(i) + [name]).join("::") })
  candidates.each { |candidate| return candidate if $classes.key?(candidate) || $constants.include?(candidate) }

  # Inside Admin::CodForm, a bare `CodForm::X` means Admin::CodForm::X to Ruby: report it as such.
  in_module_namespace = NAMESPACE_ROOTS.any? { |root| name == root || name.start_with?("#{root}::") }
  in_module_namespace ? nil : :external
end

def parse(path)
  result = Prism.parse_file(path)
  problem("syntax", "#{rel(path)}: #{result.errors.first.message}") if result.failure?
  result.value
end

module_files = MODULE_GLOBS.flat_map { |glob| Dir[File.join(ROOT, glob)] }.uniq.sort
reference_files = REFERENCE_ONLY.map { |file| File.join(ROOT, file) }.select { |file| File.exist?(file) }

module_files.each { |file| walk(parse(file), file, [], { visibility: :public, singleton: false, owner: nil }, true) }
definition_count = $references.size
$references.clear
(module_files + reference_files).each { |file| walk(parse(file), file, [], { visibility: :public, singleton: false, owner: nil }, false) }

# ---- 1 + 2: constants and method calls --------------------------------------------------------

def superclass_chain(info)
  chain = []
  current = info
  while current && current.superclass
    chain << current.superclass
    parent = $classes[current.superclass] || $classes[resolve(current.superclass, current.name.split("::")[0..-2]).to_s]
    current = parent
  end
  chain
end

def framework_methods(info)
  chain = superclass_chain(info)
  return AR_CLASS_METHODS if chain.include?("ApplicationRecord")
  return JOB_CLASS_METHODS if chain.include?("ApplicationJob")

  Set.new
end

def find_singleton(info, method)
  current = info
  while current
    return [current, current.singleton[method]] if current.singleton.key?(method)

    parent_name = current.superclass
    current = parent_name && ($classes[parent_name] || $classes[resolve(parent_name, current.name.split("::")[0..-2]).to_s])
  end
  nil
end

def call_shape(call)
  args = call.arguments ? call.arguments.arguments : []
  positional = 0
  keywords = []
  unknown = false
  args.each do |arg|
    type = arg.class.name.split("::").last
    case type
    when "KeywordHashNode"
      arg.elements.each do |element|
        if element.class.name.end_with?("AssocNode") && element.key.class.name.end_with?("SymbolNode")
          keywords << element.key.unescaped.to_sym
        else
          unknown = true # **splat or a non-symbol key
        end
      end
    when "SplatNode", "ForwardingArgumentsNode", "BlockArgumentNode"
      unknown = true unless type == "BlockArgumentNode"
    else
      positional += 1
    end
  end
  [positional, keywords, unknown]
end

def check_arity(sig, call, label, where)
  return if sig.nil? || sig.forwarding

  positional, keywords, unknown = call_shape(call)
  return if unknown

  accepts_keywords = sig.key_rest || sig.key_required.any? || sig.key_optional.any?
  # Keywords passed to a method without keyword parameters arrive as one trailing Hash.
  if keywords.any? && !accepts_keywords
    positional += 1
    keywords = []
  end
  max = sig.rest ? Float::INFINITY : sig.required + sig.optional
  if positional < sig.required || positional > max
    problem("arity", "#{where} #{label}: #{positional} positional argument(s), method takes #{sig.required}#{sig.optional.positive? ? "..#{sig.required + sig.optional}" : ''}#{sig.rest ? '+' : ''}")
  end
  missing = sig.key_required - keywords
  problem("arity", "#{where} #{label}: missing keyword(s) #{missing.join(', ')}") if missing.any?
  extra = keywords - sig.key_required - sig.key_optional
  problem("arity", "#{where} #{label}: unknown keyword(s) #{extra.join(', ')}") if extra.any? && !sig.key_rest
end

jobs = []
$references.each do |file, line, nesting, text, method, call|
  full = resolve(text, nesting)
  next if full == :external

  where = "#{rel(file)}:#{line}"
  if full.nil?
    problem("constant", "#{where} #{text} is not defined by any module file")
    next
  end
  $checked[:constants] += 1
  puts "ok   #{where} #{text}#{method ? ".#{method}" : ''}" if VERBOSE
  next if method.nil? || !$classes.key?(full)

  info = $classes[full]
  label = "#{full}.#{method}"
  found = find_singleton(info, method)
  if found
    owner, sig = found
    if owner.private_singleton.include?(method) && !file.end_with?(rel(owner.file))
      problem("visibility", "#{where} #{label} is private")
    end
    check_arity(sig, call, label, where)
    $checked[:calls] += 1
    next
  end

  framework = framework_methods(info)
  if %i[perform_async perform_in perform_at].include?(method) && framework.equal?(JOB_CLASS_METHODS)
    jobs << [where, info, method, call]
    next
  end
  if method == :new
    initialize = info.instance[:initialize]
    initialize ? check_arity(initialize, call, "#{full}.new", where) : nil
    $checked[:calls] += 1
    next
  end
  chain = superclass_chain(info)
  if chain.include?("ApplicationMailer") && info.instance.key?(method)
    check_arity(info.instance[method], call, label, where)
    $checked[:calls] += 1
    next
  end
  next if framework.include?(method) || ANY_CLASS_METHODS.include?(method)
  # Classes whose superclass is not a module class (controllers, dashboards, Struct, CurrentAttributes…)
  # inherit class methods this script cannot see.
  if chain.any? { |name| !$classes.key?(name) && !%w[ApplicationRecord ApplicationJob].include?(name) }
    $unchecked << "#{where} #{label} (inherited from #{chain.last}?)"
    next
  end
  if info.kind == :module && info.singleton.empty? && info.instance.empty?
    $unchecked << "#{where} #{label} (namespace module)"
    next
  end

  problem("method", "#{where} #{label} is not defined")
end

# ---- 4: Sidekiq ----------------------------------------------------------------------------------

jobs.each do |where, info, method, call|
  perform = info.instance[:perform]
  if perform.nil?
    problem("sidekiq", "#{where} #{info.name}.#{method}: the job has no #perform")
    next
  end
  positional, keywords, unknown = call_shape(call)
  next if unknown

  positional += 1 if keywords.any? # Sidekiq arguments are positional JSON values
  positional -= 1 if %i[perform_in perform_at].include?(method) # the first argument is the delay / time
  max = perform.rest ? Float::INFINITY : perform.required + perform.optional
  if positional < perform.required || positional > max || perform.key_required.any?
    problem("sidekiq", "#{where} #{info.name}.#{method} passes #{positional} job argument(s), #perform takes #{perform.required}..#{max}")
  end
  $checked[:jobs] += 1
end

schedule = YAML.safe_load(File.read(File.join(ROOT, "config/schedule.yml"))) || {}
schedule.each do |key, entry|
  klass = entry.is_a?(Hash) ? entry["class"].to_s : ""
  next unless klass.start_with?("CodForm::")

  info = $classes[klass]
  if info.nil? || info.instance[:perform].nil?
    problem("cron", "config/schedule.yml #{key}: #{klass} is not a job with #perform")
  elsif info.instance[:perform].required.positive?
    problem("cron", "config/schedule.yml #{key}: #{klass}#perform needs arguments, cron passes none")
  else
    $checked[:cron] += 1
  end
end

# ---- 3: Zeitwerk ---------------------------------------------------------------------------------

def camelize(segment)
  segment.split("_").map { |part| part[0].upcase + part[1..] }.join
end

module_files.each do |file|
  path = rel(file)
  next unless path.start_with?("app/")

  parts = path.delete_suffix(".rb").split("/")[2..] # drop "app/<root>"
  parts = parts[1..] if parts.first == "concerns"
  collapsed = COLLAPSED.find { |dir| path.start_with?("#{dir}/") }
  parts.delete_at(parts.index(File.basename(collapsed))) if collapsed
  expected = parts.map { |segment| camelize(segment) }.join("::")
  defined_here = $classes.select { |_name, info| info.file == file }.keys
  if $classes.key?(expected) || $constants.include?(expected)
    $checked[:zeitwerk] += 1
  else
    problem("zeitwerk", "#{path} must define #{expected} (defines #{defined_here.join(', ')})")
  end

  # A require_relative of an autoloaded file must be guarded, or Zeitwerk loses track of it.
  lines = File.readlines(file)
  lines.each_with_index do |line, index|
    next unless line.match?(/^\s*require_relative\b/)

    guarded = lines[[index - 3, 0].max..index].any? { |previous| previous.include?("unless defined?(::Rails)") }
    problem("zeitwerk", "#{path}:#{index + 1} unguarded require_relative in an autoloaded file") unless guarded
    literal = line[/require_relative\s+["']([^"']+)["']/, 1]
    next if literal.nil? # `require_relative name` inside a %w[...] loop

    target = File.expand_path("#{literal}.rb", File.dirname(file))
    problem("zeitwerk", "#{path}:#{index + 1} require_relative target does not exist") unless File.exist?(target)
  end
end
initializer = File.read(File.join(ROOT, "config/initializers/cod_form.rb"))
COLLAPSED.each do |dir|
  problem("zeitwerk", "config/initializers/cod_form.rb does not collapse #{dir}") unless initializer.include?("collapse(Rails.root.join(\"#{dir}\")")
end

# ---- 5: mailer -----------------------------------------------------------------------------------

mailer = $classes["CodFormMailer"]
locale = YAML.safe_load(File.read(File.join(ROOT, "config/locales/en.yml")))
lookup = ->(key) { key.split(".").reduce(locale["en"]) { |node, part| node.is_a?(Hash) ? node[part] : nil } }
if mailer
  actions = mailer.instance.keys - mailer.private_instance.to_a - [:initialize]
  actions.each do |action|
    views = Dir[File.join(ROOT, "app/views/cod_form_mailer/#{action}.*")]
    views.empty? ? problem("mailer", "app/views/cod_form_mailer/#{action}.* is missing") : $checked[:mailer_views] += 1
  end
  sources = [mailer.file] + Dir[File.join(ROOT, "app/views/cod_form_mailer/*")]
  sources.each do |source|
    action = File.basename(source).split(".").first
    File.read(source).scan(/\b(?:I18n\.)?t\(\s*["']([a-z0-9_.]+)["']/).flatten.each do |key|
      full = key.start_with?(".") ? "cod_form_mailer.#{action}#{key}" : key
      lookup.call(full).nil? ? problem("i18n", "#{rel(source)}: #{full} is not in config/locales/en.yml") : $checked[:i18n] += 1
    end
  end
  # Keys built at run time ("cod_form_mailer.usage_notice.subject_#{level}"): every key under the mailer scope must be a String.
  $unchecked << "interpolated i18n keys in #{rel(mailer.file)}" if File.read(mailer.file).match?(/t\(\s*"[^"]*#\{/)
end

# ---- 6: routes -----------------------------------------------------------------------------------

REST = { index: :index, show: :show, create: :create, update: :update, destroy: :destroy, new: :new, edit: :edit }.freeze
routes = File.read(File.join(ROOT, "config/routes.rb"))

def action?(controller, action, where)
  info = $classes[controller]
  if info.nil?
    problem("route", "#{where}: controller #{controller} does not exist")
  elsif info.instance.key?(action) && !info.private_instance.include?(action)
    $checked[:routes] += 1
  elsif superclass_chain(info).include?("Admin::ApplicationController") && REST.key?(action)
    $checked[:routes] += 1 # Administrate supplies the REST actions
  else
    problem("route", "#{where}: #{controller}##{action} is not a public action")
  end
end

def routes_in(block, prefix)
  block.each_line do |line|
    next if line.strip.start_with?("#")

    if (match = line.match(/to:\s*['"]([a-z_\/]+)#([a-z_]+)['"]/))
      controller = match[1].split("/").map { |segment| camelize(segment) }.join("::")
      controller = "#{prefix}::#{controller}" unless prefix.empty? || match[1].start_with?("cod_form_admin/")
      action?("#{controller}Controller", match[2].to_sym, line.strip[0, 70])
    elsif (match = line.match(/resources\s+:([a-z_]+)(.*)/))
      controller = "#{prefix}::#{camelize(match[1])}Controller"
      only = match[2][/only:\s*%i\[([a-z_ ]+)\]/, 1]
      actions = only ? only.split.map(&:to_sym) : REST.keys - (match[2][/except:\s*%i\[([a-z_ ]+)\]/, 1].to_s.split.map(&:to_sym))
      actions.each { |action| action?(controller, action, "resources :#{match[1]}") }
      @current_resource = controller
    elsif @current_resource && (match = line.match(/(?:member|collection)\s*\{([^}]*)\}/))
      match[1].scan(/(?:post|get|put|patch|delete)\s+:([a-z_]+)/).flatten.each { |action| action?(@current_resource, action.to_sym, line.strip[0, 70]) }
    end
  end
end

storefront = routes[/^    namespace :form do\n.*?^    end\n/m]
admin_api = routes[/^  scope '\/cod_form', module: 'cod_form_admin'.*?^  end\n/m]
internal = routes[/^    namespace :cod_form do\n.*?^    end\n/m]
problem("route", "config/routes.rb: the storefront `namespace :form` block was not found") if storefront.nil?
problem("route", "config/routes.rb: the admin `scope '/cod_form'` block was not found") if admin_api.nil?
problem("route", "config/routes.rb: the internal admin `namespace :cod_form` block was not found") if internal.nil?
routes_in(storefront.to_s, "Api::Form")
routes_in(admin_api.to_s, "CodFormAdmin")
routes_in(internal.to_s, "Admin::CodForm")
routes.scan(/^  get '\/cod_form\/[a-z_\/]+', to: 'cod_form_admin\/([a-z_]+)#([a-z_]+)'/).each do |controller, action|
  action?("CodFormAdmin::#{camelize(controller)}Controller", action.to_sym, "public route #{controller}##{action}")
end
if admin_api && admin_api.index("forms/defaults").to_i > admin_api.index("resources :forms").to_i
  problem("route", "`forms/defaults` must be declared above `resources :forms`")
end

# ---- report --------------------------------------------------------------------------------------

puts "files: #{module_files.size} module + #{reference_files.size} edited existing; " \
     "classes/modules: #{$classes.size}; constants: #{$constants.size}; references: #{$references.size}"
puts "checked: " + $checked.sort.map { |key, count| "#{key}=#{count}" }.join(" ")
unless $unchecked.empty?
  puts "not checked (#{$unchecked.size}): inherited / dynamic — #{VERBOSE ? '' : 'run with -v to list'}"
  $unchecked.each { |line| puts "  ? #{line}" } if VERBOSE
end
if $problems.empty?
  puts "xref: OK"
else
  puts "xref: #{$problems.size} problem(s)"
  $problems.uniq.each { |line| puts "  FAIL #{line}" }
  exit 1
end
