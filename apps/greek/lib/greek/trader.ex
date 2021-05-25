defmodule Greek.Trader do
  use GenServer

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

  def start_link(%{} = args) do
    GenServer.start_link(__MODULE__, args, name: :trader)
  end

  def init(%{} = args) do
    Logger.info("Initializing new trader for symbol(#{args.symbol})")

    tick_size = fetch_tick_size(args.symbol)

    {:ok,
     %State{
       symbol: args.symbol,
       profit_interval: args.profit_interval,
       tick_size: tick_size
     }}
  end

  def handle_cast(
        {:event, %Streamer.Binance.TradeEvent{price: price}},
        %State{symbol: symbol, buy_order: nil} = state
      ) do
    quantity = 100

    {:ok, %Binance.OrderResponse{} = order} =
      Binance.order_limit_buy(symbol, quantity, price, "GTC")

    {:noreply, %{state | buy_order: order}}
  end

  def handle_cast(
        {:event,
         %Streamer.Binance.TradeEvent{
           buyer_order_id: order_id,
           quantity: quantity
         }},
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

    {:noreply, %{state | sell_order: order}}
  end

  def handle_cast(
        {:event,
         %Streamer.Binance.TradeEvent{
           seller_order_id: order_id,
           quantity: quantity
         }},
        %State{
          sell_order: %Binance.OrderResponse{
            order_id: order_id,
            orig_qty: quantity
          }
        } = state
      ) do
    Process.exit(self(), :finished)
    {:noreply, state}
  end

  def handle_cast({:event, _}, state), do: {:noreply, state}

  defp fetch_tick_size(symbol) do
    %{"filters" => filters} =
      Binance.get_exchange_info()
      |> elem(1)
      |> Map.get(:symbols)
      |> Enum.find(&(&1["symbol"] == String.upcase(symbol)))

    %{"tickSize" => tick_size} =
      filters
      |> Enum.find(&(&1["filterType"] == "PRICE_FILTER"))

    tick_size
  end

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
