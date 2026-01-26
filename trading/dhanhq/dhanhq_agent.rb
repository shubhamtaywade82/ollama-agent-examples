#!/usr/bin/env ruby
# frozen_string_literal: true

# DhanHQ Agent - Complete trading agent with data retrieval and trading operations
# Refactored with proper OOP structure, SOLID principles, and clean architecture

require "json"
require "date"
require "dhan_hq"
require "ollama_client"
require_relative "../dhanhq_tools"

# Load all modules in dependency order
require_relative "utils/instrument_helper"
require_relative "utils/rate_limiter"
require_relative "utils/parameter_normalizer"
require_relative "utils/parameter_cleaner"
require_relative "utils/trading_parameter_normalizer"
require_relative "builders/market_context_builder"
require_relative "schemas/agent_schemas"
require_relative "services/base_service"
require_relative "services/data_service"
require_relative "services/trading_service"
require_relative "indicators/technical_indicators"
require_relative "analysis/market_structure"
require_relative "analysis/pattern_recognizer"
require_relative "analysis/trend_analyzer"
require_relative "agents/base_agent"
require_relative "agents/data_agent"
require_relative "agents/trading_agent"
require_relative "agents/technical_analysis_agent"
require_relative "agents/orchestrator_agent"
require_relative "scanners/swing_scanner"
require_relative "scanners/intraday_options_scanner"

module DhanHQ
  # Main agent orchestrator
  class Agent
    def initialize(ollama_client: nil, trading_ollama_client: nil)
      @ollama_client = ollama_client || Ollama::Client.new
      @trading_ollama_client = trading_ollama_client || create_trading_client
      @data_agent = Agents::DataAgent.new(ollama_client: @ollama_client)
      @trading_agent = Agents::TradingAgent.new(ollama_client: @trading_ollama_client)
      @analysis_agent = Agents::TechnicalAnalysisAgent.new(ollama_client: @ollama_client)
      @orchestrator_agent = Agents::OrchestratorAgent.new(ollama_client: @ollama_client)
      @swing_scanner = Scanners::SwingScanner.new
      @options_scanner = Scanners::IntradayOptionsScanner.new
    end

    attr_reader :data_agent, :trading_agent, :analysis_agent, :orchestrator_agent, :swing_scanner, :options_scanner

    private

    def create_trading_client
      config = Ollama::Config.new
      config.timeout = 60
      Ollama::Client.new(config: config)
    end
  end
end

def price_range_stats(price_ranges)
  return nil unless price_ranges.is_a?(Array) && price_ranges.any?

  {
    min: price_ranges.min.round(2),
    max: price_ranges.max.round(2),
    avg: (price_ranges.sum / price_ranges.length).round(2),
    count: price_ranges.length
  }
end

def build_expired_options_summary(stats)
  {
    data_points: stats[:data_points] || 0,
    avg_volume: stats[:avg_volume]&.round(2),
    avg_open_interest: stats[:avg_open_interest]&.round(2),
    avg_implied_volatility: stats[:avg_implied_volatility]&.round(4),
    price_range_stats: price_range_stats(stats[:price_ranges]),
    has_ohlc: stats[:has_ohlc],
    has_volume: stats[:has_volume],
    has_open_interest: stats[:has_open_interest],
    has_implied_volatility: stats[:has_implied_volatility]
  }
end

def build_option_chain_summary(chain_result)
  chain = chain_result[:result][:chain]
  underlying_price = chain_result[:result][:underlying_last_price]

  unless chain.is_a?(Hash)
    return [{ expiry: chain_result[:result][:expiry], chain_type: chain.class },
            underlying_price]
  end

  strike_prices = chain.keys.sort_by(&:to_f)
  first_strike_data = strike_prices.any? ? chain[strike_prices.first] : nil
  atm_strike = select_atm_strike(strike_prices, underlying_price)
  atm_data = atm_strike ? chain[atm_strike] : nil
  sample_greeks = build_sample_greeks(atm_data, atm_strike)

  summary = {
    expiry: chain_result[:result][:expiry],
    underlying_last_price: underlying_price,
    strikes_count: strike_prices.length,
    has_call_options: option_type_present?(first_strike_data, "ce"),
    has_put_options: option_type_present?(first_strike_data, "pe"),
    has_greeks: sample_greeks.any?,
    strike_range: strike_range_summary(strike_prices),
    sample_greeks: sample_greeks.any? ? sample_greeks : nil
  }

  [summary, underlying_price]
end

def select_atm_strike(strike_prices, underlying_price)
  return strike_prices.first unless underlying_price && strike_prices.any?

  strike_prices.min_by { |strike| (strike.to_f - underlying_price).abs }
end

def option_type_present?(strike_data, key)
  strike_data.is_a?(Hash) && (strike_data.key?(key) || strike_data.key?(key.to_sym))
end

def strike_range_summary(strike_prices)
  return nil if strike_prices.empty?

  {
    min: strike_prices.first,
    max: strike_prices.last,
    sample_strikes: strike_prices.first(5)
  }
end

def build_sample_greeks(atm_data, atm_strike)
  return {} unless atm_data.is_a?(Hash)

  sample = {}
  call_data = atm_data["ce"] || atm_data[:ce]
  put_data = atm_data["pe"] || atm_data[:pe]

  call_greeks = extract_greeks(call_data)
  sample[:call] = greeks_summary(call_greeks, call_data, atm_strike) if call_greeks

  put_greeks = extract_greeks(put_data)
  sample[:put] = greeks_summary(put_greeks, put_data, atm_strike) if put_greeks

  sample
end

def extract_greeks(option_data)
  return nil unless option_data.is_a?(Hash)
  return nil unless option_data.key?("greeks") || option_data.key?(:greeks)

  option_data["greeks"] || option_data[:greeks]
end

def greeks_summary(greeks, option_data, atm_strike)
  {
    strike: atm_strike,
    delta: greeks["delta"] || greeks[:delta],
    theta: greeks["theta"] || greeks[:theta],
    gamma: greeks["gamma"] || greeks[:gamma],
    vega: greeks["vega"] || greeks[:vega],
    iv: option_data["implied_volatility"] || option_data[:implied_volatility],
    oi: option_data["oi"] || option_data[:oi],
    last_price: option_data["last_price"] || option_data[:last_price]
  }
end

def format_score_breakdown(details)
  "Trend=#{details[:trend]}, RSI=#{details[:rsi]}, MACD=#{details[:macd]}, " \
    "Structure=#{details[:structure]}, Patterns=#{details[:patterns]}"
end

def format_option_setup_details(setup)
  iv = setup[:iv]&.round(2) || "N/A"
  oi = setup[:oi] || "N/A"
  volume = setup[:volume] || "N/A"
  "IV: #{iv}% | OI: #{oi} | Volume: #{volume}"
end

def handle_option_chain_result(chain_result)
  if chain_result[:result] && chain_result[:result][:chain]
    chain_summary, underlying_price = build_option_chain_summary(chain_result)
    puts "   ✅ Option chain retrieved for expiry: #{chain_result[:result][:expiry]}"
    puts "   📊 Underlying LTP: #{underlying_price}" if underlying_price
    puts "   📊 Chain summary: #{JSON.pretty_generate(chain_summary)}"
  elsif chain_result[:error]
    puts "   ⚠️  Could not retrieve option chain data: #{chain_result[:error]}"
  end
end

# Main execution
if __FILE__ == $PROGRAM_NAME
  # Configure DhanHQ
  begin
    DhanHQ.configure_with_env
    puts "✅ DhanHQ configured"
  rescue StandardError => e
    puts "⚠️  DhanHQ configuration error: #{e.message}"
    puts "   Make sure CLIENT_ID and ACCESS_TOKEN are set in ENV"
    puts "   Continuing with mock data for demonstration..."
  end

  puts "=" * 60
  puts "DhanHQ Agent: Ollama (Reasoning) + DhanHQ (Data & Trading)"
  puts "=" * 60
  puts

  # Initialize agent
  agent = DhanHQ::Agent.new

  # ============================================================
  # DATA AGENT EXAMPLES
  # ============================================================
  puts "─" * 60
  puts "DATA AGENT: Market Data Retrieval"
  puts "─" * 60
  puts

  # Example 1: Analyze market and decide data action (using real data)
  puts "Example 1: Market Analysis & Data Decision (Real Data)"
  puts "─" * 60

  # Fetch real market data first
  puts "📊 Fetching real market data from DhanHQ..."

  market_data = {}
  begin
    nifty_result = DhanHQDataTools.get_live_ltp(symbol: "NIFTY", exchange_segment: "IDX_I")
    sleep(1.2)
    if nifty_result.is_a?(Hash) && nifty_result[:result] && !nifty_result[:error]
      market_data[:nifty] = nifty_result[:result]
      ltp = nifty_result[:result][:ltp]
      if ltp && ltp != 0
        puts "  ✅ NIFTY: LTP=#{ltp}"
      else
        puts "  ⚠️  NIFTY: Data retrieved but LTP is null/empty (may be outside market hours)"
        puts "     Result: #{JSON.pretty_generate(nifty_result[:result])}"
      end
    elsif nifty_result && nifty_result[:error]
      puts "  ⚠️  NIFTY data error: #{nifty_result[:error]}"
    else
      puts "  ⚠️  NIFTY: No data returned"
    end
  rescue StandardError => e
    puts "  ⚠️  NIFTY data error: #{e.message}"
  end

  begin
    reliance_result = DhanHQDataTools.get_live_ltp(symbol: "RELIANCE", exchange_segment: "NSE_EQ")
    sleep(1.2)
    if reliance_result.is_a?(Hash) && reliance_result[:result] && !reliance_result[:error]
      market_data[:reliance] = reliance_result[:result]
      ltp = reliance_result[:result][:ltp]
      if ltp && ltp != 0
        puts "  ✅ RELIANCE: LTP=#{ltp}"
      else
        puts "  ⚠️  RELIANCE: Data retrieved but LTP is null/empty (may be outside market hours)"
        puts "     Result: #{JSON.pretty_generate(reliance_result[:result])}"
      end
    elsif reliance_result && reliance_result[:error]
      puts "  ⚠️  RELIANCE data error: #{reliance_result[:error]}"
    else
      puts "  ⚠️  RELIANCE: No data returned"
    end
  rescue StandardError => e
    puts "  ⚠️  RELIANCE data error: #{e.message}"
  end

  begin
    positions_result = { action: "check_positions", result: { positions: [], count: 0 },
                         note: "Positions API not available in Data Tools" }
    if positions_result[:result]
      market_data[:positions] = positions_result[:result][:positions] || []
      puts "  ✅ Positions: #{positions_result[:result][:count] || 0} active"
    else
      puts "  ✅ Positions: 0 active (Positions API not in Data Tools)"
      market_data[:positions] = []
    end
  rescue StandardError => e
    puts "  ⚠️  Positions error: #{e.message}"
    market_data[:positions] = []
  end

  puts

  # Build market context from real data
  market_context = DhanHQ::Builders::MarketContextBuilder.build(market_data)

  puts "Market Context (from real data):"
  puts market_context
  puts

  begin
    puts "🤔 Analyzing market with Ollama..."
    decision = agent.data_agent.analyze_and_decide(market_context: market_context)

    puts "\n📋 Decision:"
    if decision.is_a?(Hash)
      puts "   Action: #{decision['action'] || 'N/A'}"
      puts "   Reasoning: #{decision['reasoning'] || 'N/A'}"
      if decision["confidence"]
        puts "   Confidence: #{(decision['confidence'] * 100).round}%"
      else
        puts "   Confidence: N/A"
      end
      puts "   Parameters: #{JSON.pretty_generate(decision['parameters'] || {})}"
    else
      puts "   ⚠️  Invalid decision returned: #{decision.inspect}"
    end

    if decision["action"] != "no_action"
      puts "\n⚡ Executing data retrieval..."
      result = agent.data_agent.execute_decision(decision)
      puts "   Result: #{JSON.pretty_generate(result)}"
    end
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
  end

  puts
  puts "─" * 60
  puts "Example 2: All Data APIs Demonstration"
  puts "─" * 60
  puts "Demonstrating all available DhanHQ Data APIs:"
  puts

  test_symbol = "RELIANCE"
  test_exchange = "NSE_EQ"

  # 1. Market Quote
  puts "1️⃣  Market Quote API"
  begin
    result = DhanHQDataTools.get_market_quote(symbol: test_symbol, exchange_segment: test_exchange)
    if result[:result]
      puts "   ✅ Market Quote retrieved"
      puts "   📊 Quote data: #{JSON.pretty_generate(result[:result][:quote])}"
    else
      puts "   ⚠️  #{result[:error]}"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  sleep(1.2)

  # 2. Live Market Feed (LTP)
  puts "2️⃣  Live Market Feed API (LTP)"
  begin
    result = DhanHQDataTools.get_live_ltp(symbol: test_symbol, exchange_segment: test_exchange)
    if result[:result]
      puts "   ✅ LTP retrieved"
      puts "   📊 LTP: #{result[:result][:ltp].inspect}"
    else
      puts "   ⚠️  #{result[:error]}"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  sleep(1.2)

  # 3. Full Market Depth
  puts "3️⃣  Full Market Depth API"
  begin
    result = DhanHQDataTools.get_market_depth(symbol: test_symbol, exchange_segment: test_exchange)
    if result[:result]
      puts "   ✅ Market Depth retrieved"
      puts "   📊 Buy depth: #{result[:result][:buy_depth]&.length || 0} levels"
      puts "   📊 Sell depth: #{result[:result][:sell_depth]&.length || 0} levels"
      puts "   📊 LTP: #{result[:result][:ltp]}"
      puts "   📊 Volume: #{result[:result][:volume]}"
    else
      puts "   ⚠️  #{result[:error]}"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  sleep(1.2)

  # 4. Historical Data
  puts "4️⃣  Historical Data API"
  begin
    to_date = Date.today.strftime("%Y-%m-%d")
    from_date = (Date.today - 30).strftime("%Y-%m-%d")
    result = DhanHQDataTools.get_historical_data(
      symbol: test_symbol,
      exchange_segment: test_exchange,
      from_date: from_date,
      to_date: to_date
    )
    if result[:result]
      puts "   ✅ Historical data retrieved"
      puts "   📊 Type: #{result[:type]}"
      puts "   📊 Records: #{result[:result][:count]}"
      if result[:result][:count].zero?
        puts "   ⚠️  No data found for date range #{from_date} to #{to_date}"
        puts "      (This may be normal if market was closed or data unavailable)"
      end
    else
      puts "   ⚠️  #{result[:error]}"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  sleep(0.5)

  # 5. Expired Options Data
  puts "5️⃣  Expired Options Data API"
  begin
    result = DhanHQDataTools.get_expired_options_data(
      security_id: "13",
      exchange_segment: "NSE_FNO",
      expiry_date: (Date.today - 7).strftime("%Y-%m-%d"),
      instrument: "OPTIDX",
      expiry_flag: "MONTH",
      expiry_code: 1,
      strike: "ATM",
      drv_option_type: "CALL",
      interval: "1"
    )
    if result[:result]
      puts "   ✅ Expired options data retrieved"
      puts "   📊 Expiry: #{result[:result][:expiry_date]}"
      if result[:result][:summary_stats]
        stats = result[:result][:summary_stats]
        concise_summary = build_expired_options_summary(stats)
        puts "   📊 Data summary: #{JSON.pretty_generate(concise_summary)}"
      else
        puts "   📊 Data available but summary stats not found"
      end
    else
      puts "   ⚠️  #{result[:error]}"
      puts "      (Note: Options may require specific symbol format or may not exist for this instrument)"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  sleep(0.5)

  # 6. Option Chain
  puts "6️⃣  Option Chain API"
  begin
    expiry_list_result = DhanHQDataTools.get_option_chain(
      symbol: "NIFTY",
      exchange_segment: "IDX_I"
    )
    if expiry_list_result[:result] && expiry_list_result[:result][:expiries]
      expiries = expiry_list_result[:result][:expiries]
      puts "   ✅ Available expiries: #{expiry_list_result[:result][:count]}"
      puts "   📊 First few expiries: #{expiries.first(3).inspect}" if expiries.is_a?(Array) && !expiries.empty?

      next_expiry = expiries.is_a?(Array) && !expiries.empty? ? expiries.first : nil
      if next_expiry
        puts "   📊 Fetching option chain for next expiry: #{next_expiry}"
        chain_result = DhanHQDataTools.get_option_chain(
          symbol: "NIFTY",
          exchange_segment: "IDX_I",
          expiry: next_expiry
        )
        handle_option_chain_result(chain_result)
      end
    elsif expiry_list_result[:error]
      puts "   ⚠️  #{expiry_list_result[:error]}"
      puts "      (Note: Options may require specific symbol format or may not exist for this instrument)"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  puts "=" * 60
  puts "TRADING AGENT: Order Parameter Building"
  puts "=" * 60
  puts

  # ============================================================
  # TRADING AGENT EXAMPLES
  # ============================================================
  puts "Example 1: Simple Buy Order"
  puts "─" * 60

  market_context = <<~CONTEXT
    RELIANCE is showing strong momentum.
    Current LTP: 2850
    Entry price: 2850
    Quantity: 100 shares
    Use regular order. security_id="1333", exchange_segment="NSE_EQ"
  CONTEXT

  puts "Market Context:"
  puts market_context
  puts

  begin
    puts "🤔 Analyzing with Ollama..."
    decision = agent.trading_agent.analyze_and_decide(market_context: market_context)

    puts "\n📋 Decision:"
    if decision.is_a?(Hash)
      puts "   Action: #{decision['action'] || 'N/A'}"
      puts "   Reasoning: #{decision['reasoning'] || 'N/A'}"
      puts "   Confidence: #{(decision['confidence'] * 100).round}%" if decision["confidence"]
      puts "   Parameters: #{JSON.pretty_generate(decision['parameters'] || {})}"
    end

    if decision["action"] != "no_action"
      puts "\n⚡ Building order parameters (order not placed)..."
      result = agent.trading_agent.execute_decision(decision)
      puts "   Result: #{JSON.pretty_generate(result)}"
      if result.is_a?(Hash) && result[:order_params]
        puts "\n   📝 Order Parameters Ready:"
        puts "      #{JSON.pretty_generate(result[:order_params])}"
        puts "   💡 To place order: DhanHQ::Models::Order.new(result[:order_params]).save"
      end
    end
  rescue Ollama::TimeoutError => e
    puts "⏱️  Timeout: #{e.message}"
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
  end

  puts
  puts "=" * 60
  puts "TECHNICAL ANALYSIS EXAMPLES"
  puts "=" * 60
  puts

  # ============================================================
  # TECHNICAL ANALYSIS EXAMPLES
  # ============================================================
  puts "Example 1: Technical Analysis for RELIANCE"
  puts "─" * 60

  begin
    analysis_result = agent.analysis_agent.analyze_symbol(
      symbol: "RELIANCE",
      exchange_segment: "NSE_EQ"
    )

    if analysis_result[:error]
      puts "   ⚠️  Error: #{analysis_result[:error]}"
    elsif analysis_result[:analysis].nil? || analysis_result[:analysis].empty?
      puts "   ⚠️  Error: Analysis returned empty result"
    else
      analysis = analysis_result[:analysis]
      puts "   ✅ Analysis Complete"
      puts "   📊 Trend: #{analysis[:trend]&.dig(:trend) || 'N/A'} (#{analysis[:trend]&.dig(:strength) || 0}% strength)"
      puts "   📊 RSI: #{analysis[:indicators]&.dig(:rsi)&.round(2) || 'N/A'}"
      puts "   📊 MACD: #{analysis[:indicators]&.dig(:macd)&.round(2) || 'N/A'}"
      puts "   📊 Current Price: #{analysis[:current_price] || 'N/A'}"
      puts "   📊 Patterns Detected: #{analysis[:patterns]&.dig(:candlestick)&.length || 0} candlestick patterns"
      puts "   📊 Structure Break: #{analysis[:structure_break]&.dig(:broken) ? 'Yes' : 'No'}"

      # Generate swing trading recommendation
      begin
        recommendation = agent.analysis_agent.generate_recommendation(
          analysis_result,
          trading_style: :swing
        )

        if recommendation && !recommendation[:error] && recommendation.is_a?(Hash)
          puts "\n   💡 Swing Trading Recommendation:"
          puts "      Action: #{recommendation['recommendation']&.upcase || 'N/A'}"
          puts "      Entry: #{recommendation['entry_price'] || 'N/A'}"
          puts "      Stop Loss: #{recommendation['stop_loss'] || 'N/A'}"
          puts "      Target: #{recommendation['target_price'] || 'N/A'}"
          puts "      Risk/Reward: #{recommendation['risk_reward_ratio']&.round(2) || 'N/A'}"
          puts "      Confidence: #{(recommendation['confidence'] * 100).round}%" if recommendation["confidence"]
        end
      rescue StandardError => e
        puts "   ⚠️  Could not generate recommendation: #{e.message}"
      end
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end

  puts
  puts "Example 2: Swing Trading Scanner"
  puts "─" * 60

  begin
    # Scan a few symbols for swing opportunities
    symbols_to_scan = ["RELIANCE", "TCS", "INFY"]
    puts "   🔍 Scanning #{symbols_to_scan.length} symbols for swing opportunities..."

    candidates = agent.swing_scanner.scan_symbols(
      symbols_to_scan,
      exchange_segment: "NSE_EQ",
      min_score: 40,
      verbose: true
    )

    if candidates.empty?
      puts "   ⚠️  No swing candidates found above minimum score (40/100)"
      puts "      Try lowering min_score or check rejected candidates above"
    else
      puts "   ✅ Found #{candidates.length} swing candidates:"
      candidates.each do |candidate|
        puts "      📈 #{candidate[:symbol]}: Score #{candidate[:score]}/100"
        if candidate[:score_details]
          details = candidate[:score_details]
          puts "         Breakdown: #{format_score_breakdown(details)}"
        end
        trend = candidate[:analysis][:trend]
        puts "         Trend: #{trend[:trend]} (#{trend[:strength]}% strength)"
        puts "         #{candidate[:interpretation]}"
      end
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
    puts "   #{e.backtrace.first(3).join("\n   ")}" if e.backtrace
  end

  puts
  puts "Example 3: Intraday Options Scanner"
  puts "─" * 60

  begin
    puts "   🔍 Scanning NIFTY for intraday options opportunities..."

    options_setups = agent.options_scanner.scan_for_options_setups(
      "NIFTY",
      exchange_segment: "IDX_I",
      min_score: 40,
      verbose: true
    )

    if options_setups[:error]
      puts "   ⚠️  #{options_setups[:error]}"
    elsif options_setups[:setups] && !options_setups[:setups].empty?
      puts "   ✅ Found #{options_setups[:setups].length} options setups:"
      options_setups[:setups].each do |setup|
        puts "      📊 #{setup[:type].to_s.upcase} @ #{setup[:strike]}"
        puts "         #{format_option_setup_details(setup)}"
        puts "         Score: #{setup[:score]}/100 | Recommendation: #{setup[:recommendation]}"
      end
    else
      puts "   ⚠️  No options setups found above minimum score (40/100)"
      puts "      Check rejected setups above or try lowering min_score"
    end
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
    puts "   #{e.backtrace.first(3).join("\n   ")}" if e.backtrace
  end

  puts
  puts "=" * 60
  puts "TOOL CALLING EXAMPLE (Using Executor + Structured Tool Classes)"
  puts "=" * 60
  puts

  # ============================================================
  # TOOL CALLING WITH EXECUTOR
  # ============================================================
  puts "Example: Agentic Tool Calling with DhanHQ Tools"
  puts "─" * 60
  puts "This demonstrates the new tool calling pattern using:"
  puts "  - Structured Tool classes (type-safe schemas)"
  puts "  - Executor (automatic tool execution loop)"
  puts "  - chat_raw() internally (via Executor)"
  puts

  # Define DhanHQ tools using structured Tool classes
  market_quote_tool = Ollama::Tool.new(
    type: "function",
    function: Ollama::Tool::Function.new(
      name: "get_market_quote",
      description: "Get market quote for a symbol. Returns OHLC, depth, volume, and other market data. " \
                   "Finds instrument automatically using exchange_segment and symbol.",
      parameters: Ollama::Tool::Function::Parameters.new(
        type: "object",
        properties: {
          symbol: Ollama::Tool::Function::Parameters::Property.new(
            type: "string",
            description: "Stock or index symbol (e.g., RELIANCE, NIFTY)"
          ),
          exchange_segment: Ollama::Tool::Function::Parameters::Property.new(
            type: "string",
            description: "Exchange segment",
            enum: %w[NSE_EQ NSE_FNO BSE_EQ BSE_FNO IDX_I]
          )
        },
        required: %w[symbol exchange_segment]
      )
    )
  )

  live_ltp_tool = Ollama::Tool.new(
    type: "function",
    function: Ollama::Tool::Function.new(
      name: "get_live_ltp",
      description: "Get live last traded price (LTP) for a symbol. Fast API for current price. " \
                   "Finds instrument automatically using exchange_segment and symbol.",
      parameters: Ollama::Tool::Function::Parameters.new(
        type: "object",
        properties: {
          symbol: Ollama::Tool::Function::Parameters::Property.new(
            type: "string",
            description: "Stock or index symbol"
          ),
          exchange_segment: Ollama::Tool::Function::Parameters::Property.new(
            type: "string",
            description: "Exchange segment",
            enum: %w[NSE_EQ NSE_FNO BSE_EQ BSE_FNO IDX_I]
          )
        },
        required: %w[symbol exchange_segment]
      )
    )
  )

  # Define tools with structured Tool classes and callables
  tools = {
    "get_market_quote" => {
      tool: market_quote_tool,
      callable: lambda do |symbol:, exchange_segment:|
        result = DhanHQDataTools.get_market_quote(
          symbol: symbol.to_s,
          exchange_segment: exchange_segment.to_s
        )

        if result[:error]
          { error: result[:error] }
        else
          quote = result[:result][:quote]
          {
            symbol: symbol,
            exchange_segment: exchange_segment,
            last_price: quote[:last_price],
            volume: quote[:volume],
            ohlc: quote[:ohlc],
            change_percent: quote[:net_change]
          }
        end
      rescue StandardError => e
        { error: e.message }
      end
    },

    "get_live_ltp" => {
      tool: live_ltp_tool,
      callable: lambda do |symbol:, exchange_segment:|
        result = DhanHQDataTools.get_live_ltp(
          symbol: symbol.to_s,
          exchange_segment: exchange_segment.to_s
        )

        if result[:error]
          { error: result[:error] }
        else
          {
            symbol: symbol,
            exchange_segment: exchange_segment,
            ltp: result[:result][:ltp],
            timestamp: result[:result][:timestamp]
          }
        end
      rescue StandardError => e
        { error: e.message }
      end
    }
  }

  # Create executor with tools
  # Create client with same configuration as other examples
  executor_config = Ollama::Config.new
  executor_config.model = ENV.fetch("OLLAMA_MODEL", "llama3.1:8b")
  executor_config.temperature = 0.2
  executor_config.timeout = 60
  executor_client = Ollama::Client.new(config: executor_config)

  executor = Ollama::Agent::Executor.new(
    executor_client,
    tools: tools,
    max_steps: 10
  )

  begin
    puts "🔄 Starting agentic tool-calling loop..."
    puts "User query: Get market quote for RELIANCE and also check NIFTY's current price"
    puts

    result = executor.run(
      system: "You are a market data assistant. Use the available tools to get market data. " \
              "You can call multiple tools in sequence. When you have the data, summarize it for the user.",
      user: "Get market quote for RELIANCE stock and also check NIFTY's current price"
    )

    puts
    puts "=" * 60
    puts "Tool Calling Result:"
    puts "=" * 60
    puts result
    puts
  rescue Ollama::Error => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace.first(5).join("\n") if e.backtrace
  rescue StandardError => e
    puts "❌ Unexpected error: #{e.message}"
    puts e.backtrace.first(3).join("\n") if e.backtrace
  end

  puts
  puts "=" * 60
  puts "DhanHQ Agent Summary:"
  puts "  ✅ Ollama: Reasoning & Decision Making"
  puts "  ✅ DhanHQ: Data Retrieval & Order Building"
  puts "  ✅ Data APIs: Market Quote, Live Market Feed, Full Market Depth, " \
       "Historical Data, Expired Options Data, Option Chain"
  puts "  ✅ Trading Tools: Order parameters, Super order parameters, Cancel parameters"
  puts "  ✅ Technical Analysis: Trend analysis, SMC concepts, Pattern recognition, Indicators (RSI, MACD, MA, etc.)"
  puts "  ✅ Scanners: Swing trading scanner, Intraday options scanner"
  puts "  ✅ Analysis Agents: Technical analysis agent with LLM interpretation"
  puts "  ✅ Tool Calling: Executor with structured Tool classes (NEW!)"
  puts "=" * 60
end
