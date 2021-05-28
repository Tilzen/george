defmodule Greek.Trader do
  use GenServer, restart: :temporary

  require Logger

  defmodule State do
    @enforce_keys [:symbol, :profit_interval, :tick_size]

    defstruct [
      :symbol,
      :buy_order,
      :sell_order,
      :profit_interval,
      :tick_size
    ]
  end

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state, name: :trader)
  end

  def init(%State{} = state) do
    Phoenix.PubSub.subscribe(
      Streamer.PubSub,
      "trade:#{state.symbol}"
    )

    {:ok, state}
  end

  def handle_info(
        %Streamer.Binance.TradeEvent{price: price},
        %State{symbol: symbol, buy_order: nil} = state
      ) do
    Logger.info("Placing buy order (#{symbol}@#{price})")

    quantity = 100

    {:ok, %Binance.OrderResponse{} = order} =
      Binance.order_limit_buy(symbol, quantity, price, "GTC")

    new_state = %{state | buy_order: order}
    Greek.Leader.notify(:trader_state_updated, new_state)
    {:noreply, new_state}
  end

  def handle_info(
        %Streamer.Binance.TradeEvent{
          buyer_order_id: order_id,
          quantity: quantity
        },
        %State{
          symbol: symbol,
          buy_order: %Binance.OrderResponse{
            price: buy_price,
            order_id: order_id,
            orig_qty: quantity
          },
          profit_interval: profit_interval,
          tick_size: tick_size
        } = state
      ) do
    sell_price = calculate_sell_price(buy_price, profit_interval, tick_size)

    {:ok, %Binance.OrderResponse{} = order} =
      Binance.order_limit_sell(symbol, quantity, sell_price, "GTC")

    new_state = %{state | sell_order: order}
    Greek.Leader.notify(:trader_state_updated, new_state)
    {:noreply, new_state}
  end

  def handle_info(
        %Streamer.Binance.TradeEvent{
          seller_order_id: order_id,
          quantity: quantity
        },
        %State{
          sell_order: %Binance.OrderResponse{
            order_id: order_id,
            orig_qty: quantity
          }
        } = state
      ) do
    Logger.info("Trade finished, trader will now exit.")

    Process.exit(self(), :finished)
    {:stop, :trade_finished, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp calculate_sell_price(buy_price, profit_interval, tick_size) do
    fee = Decimal.cast("1.001")

    original_price =
      buy_price
      |> Decimal.cast()
      |> Decimal.mult(fee)

    tick = Decimal.cast(tick_size)

    net_target_price =
      original_price
      |> Decimal.mult(Decimal.add("1.0", Decimal.cast(profit_interval)))

    gross_target_price = Decimal.mult(net_target_price, fee)

    gross_target_price
    |> Decimal.div_int(tick)
    |> Decimal.mult(tick)
    |> Decimal.to_float()
  end
end
