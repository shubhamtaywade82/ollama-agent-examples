#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ollama_client'
require 'json'

# ---------------------------
# Configuration
# ---------------------------

client = Ollama::Client.new

# Discover thinking-capable models efficiently
available_models = client.list_models
THINKING_MODELS = available_models.select { |m| m.dig('capabilities', 'thinking') == true }

# Separate by size/preference
# Prefer qwen3:0.6b for planning if available, otherwise the smallest thinking model
sorted_thinking = THINKING_MODELS.sort_by { |m| m['size'] || 0 }
planner_match = sorted_thinking.find { |m| m['model'].include?('0.6b') } || sorted_thinking.first

PLANNER_MODEL = planner_match ? planner_match['model'] : 'qwen3:0.6b'
# Prefer a larger model for execution
EXECUTOR_MODEL = sorted_thinking.last ? sorted_thinking.last['model'] : 'llama3.1:8b'

THINKING_MODEL_NAMES = THINKING_MODELS.map { |m| m['model'] }
MAX_STEPS = 20

# System prompt for the executor phase
AGENT_SYSTEM_PROMPT = <<~PROMPT
  You are an AI assistant that can use tools.
  - ONLY use a tool if it is strictly necessary to answer the user's request.
  - If the user is just saying "HI" or asking a general question you can answer directly, do NOT call any tools.
  - Provide results clearly and concisely. Do not add meta-commentary about tool selection unless necessary.
PROMPT

# client = Ollama::Client.new (Moved to top)

# ---------------------------
# Helpers
# ---------------------------

def thinking_capable?(model)
  THINKING_MODEL_NAMES.include?(model.to_s)
end

def format_history(messages)
  messages.map do |m|
    role = m[:role]
    content = m[:content] || ""

    # Handle tool calls in history (handle both objects and hashes)
    tool_calls = m[:tool_calls]
    if tool_calls && tool_calls.respond_to?(:any?) && tool_calls.any?
      calls = tool_calls.map do |c|
        name = c.respond_to?(:function) ? c.function.name : (c["function"]["name"] || c[:function][:name])
        args = c.respond_to?(:function) ? c.function.arguments : (c["function"]["arguments"] || c[:function][:arguments])
        "#{name}(#{args})"
      end.join(", ")
      content += " [Tool Calls: #{calls}]"
    end

    "#{role.upcase}: #{content}"
  end.join("\n")
end

puts "Selected Planner: #{PLANNER_MODEL}"
puts "Selected Executor: #{EXECUTOR_MODEL}"
puts "Thinking Models Found: #{THINKING_MODEL_NAMES.join(', ')}" unless THINKING_MODEL_NAMES.empty?

# ---------------------------
# Tool Definitions
# ---------------------------

TOOLS = {
  'read_file' => lambda { |path:|
    begin
      File.read(path)
    rescue StandardError => e
      { error: e.message }
    end
  },

  'list_files' => lambda { |path: '.'|
    Dir.entries(path).reject { |f| f.start_with?('.') }
  },

  'calculate' => lambda { |expression:|
    begin
      result = eval(expression)
      { result: result }
    rescue StandardError => e
      { error: e.message }
    end
  }
}.freeze

# ---------------------------
# Tool Schemas exposed to LLM
# ---------------------------

TOOL_SCHEMAS = [
  {
    type: 'function',
    function: {
      name: 'read_file',
      description: 'Read contents of a file from disk',
      parameters: {
        type: 'object',
        properties: {
          path: { type: 'string' }
        },
        required: ['path']
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'list_files',
      description: 'List files in a directory',
      parameters: {
        type: 'object',
        properties: {
          path: { type: 'string' }
        }
      }
    }
  },
  {
    type: 'function',
    function: {
      name: 'calculate',
      description: 'Evaluate a math expression',
      parameters: {
        type: 'object',
        properties: {
          expression: { type: 'string' }
        },
        required: ['expression']
      }
    }
  }
].freeze

# ---------------------------
# Planner Schema
# ---------------------------

PLAN_SCHEMA = {
  'type' => 'object',
  'required' => %w[action],
  'properties' => {
    'action' => {
      'type' => 'string',
      'enum' => %w[tool respond finish]
    },
    'tool_name' => {
      'type' => 'string',
      'enum' => %w[read_file list_files calculate]
    },
    'tool_arguments' => {
      'type' => 'object'
    }
  }
}.freeze

# ---------------------------
# Planner
# ---------------------------

def plan_next_step(client, messages, model: PLANNER_MODEL)
  planner_messages = messages.dup

  planner_messages << {
    role: 'system',
    content: <<~PROMPT
      You are an AI planning agent. Decide the next action based on the conversation history.

      Available Actions:
      - tool: Use this if you need more information or to perform a calculation.
      - respond: Use this to provide a verbal reply to the user.
      - finish: Use this ONLY if you have JUST SENT the final answer to the user in a 'respond' action.

      Available Tools & Parameters:
      - read_file: { path: "string" }
      - list_files: { path: "string" }
      - calculate: { expression: "string" }

      CRITICAL:
      1. If the user's request is NOT yet answered, you MUST choose 'tool' or 'respond'.
      2. ONLY use 'finish' if the final answer is already in the history.
      3. For "hi", choose 'respond' for step 1.
    PROMPT
  }

  options = {
    messages: planner_messages,
    format: PLAN_SCHEMA,
    options: {
      temperature: 0.1 # Lower temperature for better JSON stability in small models
    }
  }

  if thinking_capable?(model)
    options[:think] = true
  end

  response = client.chat(model: model, **options)

  # reasoning is in res.message.thinking for some versions/models
  thinking = response.message.respond_to?(:thinking) ? response.message.thinking : nil

  # The small model might just return a string or truncated JSON
  content = response.message.content.to_s.strip
  plan = content.start_with?('{') ? JSON.parse(content) : { 'action' => 'respond' }

  {
    plan: plan,
    reasoning: thinking
  }
rescue JSON::ParserError
  { plan: { 'action' => 'respond' }, reasoning: nil }
end

# ---------------------------
# Tool Execution
# ---------------------------

def run_tool(tool_name, args)
  tool = TOOLS[tool_name]

  return { error: "Unknown tool #{tool_name}" } unless tool

  tool.call(**args.transform_keys(&:to_sym))
end

# ---------------------------
# Chat Executor
# ---------------------------

def execute_chat(client, messages, model: EXECUTOR_MODEL)
  pp messages
  options = {
    messages: messages,
    tools: TOOL_SCHEMAS
  }

  options[:think] = true if thinking_capable?(model)

  response = client.chat(model: model, **options)

  message = response.message

  if message.tool_calls && !message.tool_calls.empty?
    { type: :tool_call, message: message }
  else
    { type: :response, content: message.content }
  end
end

# ---------------------------
# Agent Loop
# ---------------------------

def run_agent(client, user_input)
  messages = [
    { role: 'system', content: AGENT_SYSTEM_PROMPT },
    { role: 'user', content: user_input }
  ]

  step = 0

  loop do
    step += 1

    break if step > MAX_STEPS

    puts "\n----------------------------"
    puts "STEP #{step}"
    puts '----------------------------'

    plan_response = plan_next_step(client, messages, model: PLANNER_MODEL)

    puts "\n[THINKING]"
    if plan_response[:reasoning]
      puts plan_response[:reasoning]
    else
      puts "N/A (Non-thinking model: #{PLANNER_MODEL})"
    end

    plan = plan_response[:plan]

    puts "\n[PLAN]"
    puts JSON.pretty_generate(plan)

    case plan['action']

    when 'tool'

      tool_name = plan['tool_name']
      args = plan['tool_arguments'] || {}

      puts "\n[TOOL CALL]"
      puts "#{tool_name} #{args}"

      result = run_tool(tool_name, args)

      puts "\n[TOOL RESULT]"
      puts result

      messages << {
        role: 'tool',
        tool_name: tool_name,
        content: result.to_json
      }

    when 'respond'

      response = execute_chat(client, messages, model: EXECUTOR_MODEL)

      if response[:type] == :tool_call

        message = response[:message]

        messages << {
          role: 'assistant',
          tool_calls: message.tool_calls.map(&:to_h)
        }

        message.tool_calls.each do |call|
          name = call.function.name
          args = call.function.arguments

          puts "\n[MODEL REQUESTED TOOL]"
          puts "#{name} #{args}"

          result = run_tool(name, args)

          puts "\n[TOOL RESULT]"
          puts result

          messages << {
            role: 'tool',
            tool_name: name,
            content: result.to_json
          }
        end

      else

        puts "\n[ASSISTANT]"
        puts response[:content]

        if response[:content].nil? || response[:content].strip.empty?
          puts "\n[FINISHED] (No new information from executor)"
          break
        else
          messages << {
            role: 'assistant',
            content: response[:content]
          }
        end

      end

    when 'finish'

      puts "\n[FINISHED]"
      break

    else
      puts "\nUnknown planner action"
      break

    end
  end
end

# ---------------------------
# Entry Point
# ---------------------------

if ARGV.any?
  # Handle CLI arguments: ./agent.rb "hi"
  input = ARGV.join(' ')
  run_agent(client, input)
else
  # Interactive CLI
  puts 'AI Agent Ready'
  puts "Type 'exit' to quit"

  loop do
    print "\n> "
    input = STDIN.gets&.chomp

    break if input.nil? || input == 'exit'

    run_agent(client, input)
  end
end
