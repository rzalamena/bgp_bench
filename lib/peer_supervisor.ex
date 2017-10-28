defmodule Bgp.PeerSupervisor do
  @moduledoc """
  BGP peer supervisor to make restarts in case of failures.
  """
  use Supervisor

  def start_link(peers) do
    Supervisor.start_link(__MODULE__, peers)
  end

  def init(peers) do
    Supervisor.init(peers, strategy: :one_for_one)
  end
end
