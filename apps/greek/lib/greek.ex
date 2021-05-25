defmodule Greek do
  @moduledoc """
  Documentation for `Greek`.
  """

  def send_event(%Streamer.Binance.TradeEvent{} = event) do
    GenServer.cast(:trader, {:event, event})
  end
end
