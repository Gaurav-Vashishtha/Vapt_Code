# frozen_string_literal: true

module Whatsapp
  module Ai
    class Agent
      MAX_STEPS = 5

      Result = Struct.new(:kind, :text, :intent, :reason, :note, :actions, :usage, :model, :error, keyword_init: true) do
        def reply?
          kind == :reply
        end

        def handoff?
          kind == :handoff
        end

        def failed?
          kind == :failed
        end

        def skipped?
          kind == :skipped
        end
      end

      def self.call(conversation:, setting:, history: nil, dry_run: false, allow_actions: true, note: nil,
                    client: OpenaiClient.new)
        new(conversation: conversation, setting: setting, history: history, dry_run: dry_run,
            allow_actions: allow_actions, note: note, client: client).call
      end

      def initialize(conversation:, setting:, history:, dry_run:, allow_actions:, client:, note: nil)
        @note = note
        @conversation = conversation
        @setting = setting
        @history = history
        @dry_run = dry_run
        @allow_actions = allow_actions
        @client = client
        @usage = { input: 0, cached: 0, output: 0 }
      end

      def call
        context = ContextBuilder.call(@conversation, history: @history)
        context['situation'] = @note if @note.present?
        tools = Tools.new(conversation: @conversation, setting: @setting, context: context, dry_run: @dry_run,
                          allow_actions: @allow_actions)
        definitions = tools.definitions
        messages = PromptBuilder.messages(setting: @setting, context: context, tool_names: tools.names)
        return result(:skipped, tools, error: 'no_customer_message') unless messages.last[:role] == 'user'

        MAX_STEPS.times do
          response = @client.chat(messages: messages, tools: definitions)
          track_usage(response['usage'])
          message = response.dig('choices', 0, 'message') || {}
          calls = Array(message['tool_calls'])
          if calls.empty?
            text = message['content'].to_s.strip
            return text.present? ? result(:reply, tools, text: text, intent: 'other') : result(:handoff, tools, reason: 'unsure')
          end

          messages << { role: 'assistant', content: message['content'], tool_calls: calls }
          calls.each do |call|
            name = call.dig('function', 'name').to_s
            output = tools.execute(name, call.dig('function', 'arguments'))
            if output.is_a?(Tools::Outcome)
              return finish(output, tools)
            end

            messages << { role: 'tool', tool_call_id: call['id'], content: output.to_json }
          end
        end
        result(:handoff, tools, reason: 'unsure', note: 'The assistant could not finish in time.')
      rescue OpenaiClient::Error => e
        result(:failed, tools, error: e.message)
      end

      private

      def finish(outcome, tools)
        if outcome.kind == :reply && outcome.text.blank?
          return result(:handoff, tools, reason: 'unsure', note: 'The assistant produced an empty reply.')
        end

        result(outcome.kind, tools, text: outcome.text, intent: outcome.intent, reason: outcome.reason, note: outcome.note)
      end

      def track_usage(usage)
        return unless usage.is_a?(Hash)

        @usage[:input] += usage['prompt_tokens'].to_i
        @usage[:cached] += usage.dig('prompt_tokens_details', 'cached_tokens').to_i
        @usage[:output] += usage['completion_tokens'].to_i
      end

      def result(kind, tools, text: nil, intent: nil, reason: nil, note: nil, error: nil)
        Result.new(kind: kind, text: text, intent: intent, reason: reason, note: note,
                   actions: tools ? tools.actions : [], usage: @usage, model: @client.model, error: error)
      end
    end
  end
end
