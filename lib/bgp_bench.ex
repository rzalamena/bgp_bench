defmodule BgpBench do
  @moduledoc """
  Documentation for BgpBench.
  """
  use Application

  def start(_type, _args) do
    Application.get_env(:bgp_bench, :peers)
    |> Enum.reduce([], fn(peer, acc) ->
      [{Bgp.Peer, peer} | acc]
    end)
    |> Bgp.PeerSupervisor.start_link
  end
end
