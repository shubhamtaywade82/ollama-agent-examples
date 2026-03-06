#!/usr/bin/env ruby
# frozen_string_literal: true

require 'ollama_client'
require 'json'

# ---------------------------
# Configuration
# ---------------------------

# Configure Ollama Client with specific timeout
config = Ollama::Config.new
config.timeout = 120 # Increase timeout to 120s for long thinking/processing
client = Ollama::Client.new(config: config)

# Discover thinking-capable models efficiently
available_models = client.list_models
THINKING_MODELS = available_models.select { |m| m.dig('capabilities', 'thinking') == true }

# Separate by size/preference
# Prefer qwen3:8b or similar medium model for planning if available
sorted_thinking = THINKING_MODELS.sort_by { |m| m['size'] || 0 }
planner_match = sorted_thinking.find { |m| m['model'].include?('8b') } ||
                sorted_thinking.find { |m| m['model'].include?('latest') } ||
                sorted_thinking.first

PLANNER_MODEL = planner_match ? planner_match['model'] : 'qwen3:8b'
# Prefer a larger model for execution
EXECUTOR_MODEL = sorted_thinking.last ? sorted_thinking.last['model'] : 'qwen3-vl:latest'

THINKING_MODEL_NAMES = THINKING_MODELS.map { |m| m['model'] }
MAX_STEPS = 20

# System prompt for the executor phase
AGENT_SYSTEM_PROMPT = <<~PROMPT
  You are an AI assistant that can use tools to achieve the user's goal.
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
      'type' => 'object',
      'properties' => {
        'path' => { 'type' => 'string' },
        'expression' => { 'type' => 'string' }
      }
    }
  }
}.freeze

# ---------------------------
# Planner
# ---------------------------

def plan_next_step(client, goal, observations, model: PLANNER_MODEL)
  observation_text = observations.map.with_index do |obs, i|
    "Step #{i + 1}: #{obs}"
  end.join("\n")

  prompt = <<~PROMPT
    You are an autonomous AI agent.

    Goal:
    #{goal}

    Observations so far:
    #{observation_text}

    Decide the next action.

    Available actions (MUST CHOOSE EXACTLY ONE):
    - tool: call a tool to gather data or process math.
    - respond: answer the user verbally with your final answer.
    - finish: goal achieved AND the user has already received the answer.

    Tool Parameters (STRICT JSON ONLY):
    - read_file requires EXACTLY { "path": "filename" }. Do NOT use "file_path".
    - list_files requires EXACTLY { "path": "dirname" }.
    - calculate requires EXACTLY { "expression": "ruby math expression" } (e.g. "(10+20)/2").

    Rules:
    1. If the last observation is a tool result, you MUST choose 'respond' to verbalize the result to the user.
    2. If the last observation is an 'assistant' response that provides the final answer, you MUST choose 'finish'.
    3. Do NOT include tool_name or tool_arguments if your action is 'respond' or 'finish'.
    4. If a tool failed previously with an ArgumentError, correct your parameter names (e.g. use "path", not "file_path").
  PROMPT

  planner_messages = [{ role: 'user', content: prompt }]

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

  # Reasoning is in res.message.thinking for some versions/models
  thinking = response.message.respond_to?(:thinking) ? response.message.thinking : nil

  # The small model might just return a string or truncated JSON
  content = response.message.content.to_s.strip

  begin
    plan = content.start_with?('{') ? JSON.parse(content) : { 'action' => 'respond' }

    # Validation: If the model provides tool arguments but set action to 'respond',
    # it likely meant to call a tool.
    if plan['action'] == 'respond' && plan['tool_arguments'] && !plan['tool_arguments'].empty?
      plan['action'] = 'tool'
    end

    # Fallback for tool_name if missing but arguments exist
    if plan['action'] == 'tool' && (plan['tool_name'].nil? || plan['tool_name'].empty?)
      if plan['tool_arguments']&.key?('path')
        plan['tool_name'] = 'read_file'
      elsif plan['tool_arguments']&.key?('expression')
        plan['tool_name'] = 'calculate'
      end
    end
  rescue JSON::ParserError
    plan = { 'action' => 'respond' }
  end

  {
    plan: plan,
    reasoning: thinking
  }
end

# ---------------------------
# Tool Execution
# ---------------------------

def run_tool(tool_name, args)
  tool = TOOLS[tool_name]

  return { error: "Unknown tool #{tool_name}" } unless tool

  begin
    tool.call(**args.transform_keys(&:to_sym))
  rescue => e
    { error: "#{e.class}: #{e.message}" }
  end
end

# ---------------------------
# Chat Executor
# ---------------------------

def execute_chat(client, messages, model: EXECUTOR_MODEL, allow_tools: true)
  options = {
    messages: messages
  }

  options[:tools] = TOOL_SCHEMAS if allow_tools

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
  goal = user_input
  observations = []

  messages = [
    { role: 'system', content: AGENT_SYSTEM_PROMPT },
    { role: 'user', content: goal }
  ]

  step = 0

  loop do
    step += 1

    break if step > MAX_STEPS

    puts "\n----------------------------"
    puts "STEP #{step}"
    puts '----------------------------'

    plan_response = plan_next_step(client, goal, observations, model: PLANNER_MODEL)

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

      observations << {
        tool: tool_name,
        args: args,
        result: result
      }

      call_id = "call_p#{step}"
      messages << {
        role: 'assistant',
        tool_calls: [
          {
            id: call_id,
            type: 'function',
            function: {
              name: tool_name,
              arguments: args
            }
          }
        ]
      }

      messages << {
        role: 'tool',
        name: tool_name,
        content: result.to_json
      }

    when 'respond'

      response = execute_chat(client, messages, model: EXECUTOR_MODEL, allow_tools: false)

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

          observations << {
            tool: name,
            args: args,
            result: result
          }

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
          observations << {
            assistant: response[:content]
          }

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
