defmodule Streamer.Binance do
  use WebSockex

  require Logger

  @stream_endpoint "wss://stream.binance.com:9443/ws/"

  def start_link(symbol, state) do
    symbol = String.downcase(symbol)
    url = "#{@stream_endpoint}#{symbol}@trade"

    WebSockex.start_link(url, __MODULE__, state)
  end

  def handle_frame({_type, message}, state) do
    case Jason.decode(message) do
      {:ok, event} -> handle_event(event, state)
      {:error, _} -> throw("Unable to decode message: #{message}")
    end

    {:ok, state}
  end

  def handle_event(%{"e" => "trade"} = event, _state) do
    trade_event = %Streamer.Binance.TradeEvent{
      :event_type => event["e"],
      :event_time => event["E"],
      :symbol => event["s"],
      :trade_id => event["t"],
      :price => event["p"],
      :quantity => event["q"],
      :buyer_order_id => event["b"],
      :seller_order_id => event["a"],
      :trade_time => event["T"],
      :is_buyer_market_maker? => event["m"]
    }

    Logger.debug(
      "Trade event received " <>
        "#{trade_event.symbol}@#{trade_event.price}"
    )

    Phoenix.PubSub.broadcast(
      Streamer.PubSub,
      "trade:#{trade_event.symbol}",
      trade_event
    )
  end
end
