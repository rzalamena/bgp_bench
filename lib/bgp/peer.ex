defmodule Bgp.Peer do
  @moduledoc """
  BGP peer handling library.
  """
  use GenServer
  require Logger

  defmodule Options do
    @moduledoc """
    BGP peer options.
    """
    @enforce_keys [:neighbor, :remote_as, :local_address, :local_as, :router_id]
    defstruct neighbor: nil, neighbor_port: 179, remote_as: nil,
      local_address: nil, local_as: nil, router_id: nil,
      prefix_start: {10, 0, 0, 1}, prefix_amount: 0

    @type t :: %Options{
      neighbor: :inet.ip4_address,
      neighbor_port: :inet.port_number,
      remote_as: Bgp.Protocol.as_number,
      local_address: :inet.ip4_address,
      local_as: Bgp.Protocol.as_number,
      router_id: Bgp.Protocol.router_id,
      prefix_start: :inet.ip4_address,
      prefix_amount: non_neg_integer,
    }
  end

  defmodule State do
    @moduledoc """
    BGP peer internal state
    """
    @enforce_keys [:options]
    defstruct options: nil, socket: nil, bstate: :open_sent, msgtail: <<>>,
              holdtime: 180, keepalive_timer: nil, prefix_cur: 0

    @type bgp_state :: :open_sent | :established
    @type t :: %State{
      options: Options.t,
      socket: port,
      bstate: bgp_state,
      msgtail: binary,
      holdtime: non_neg_integer,
      keepalive_timer: reference,
      prefix_cur: non_neg_integer,
    }
  end

  #
  # Client-side
  #

  @doc """
  Start peer with options.
  """
  @spec start_link(Options.t) :: GenServer.on_start
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  #
  # Server-side
  #

  def child_spec(arg) do
    id = :inet.ntoa(arg[:local_address])
    %{
      id: id,
      start: {__MODULE__, :start_link, [arg]},
      restart: :transient,
    }
  end

  def init(opts) do
    Process.send(self(), :connect, [])
    {:ok, %State{options: opts}}
  end

  def handle_info(:connect, state) do
    conn_opts = [active: :true, ip: state.options.local_address, mode: :binary]
    neighbor = state.options.neighbor
    port = state.options.neighbor_port
    case :gen_tcp.connect(neighbor, port, conn_opts) do
      {:ok, socket} ->
        :gen_tcp.send(socket, Bgp.Protocol.Open.encode(%Bgp.Protocol.Open.Options{
          bgpid: state.options.router_id,
          my_as: state.options.local_as,
          params: [
            Bgp.Protocol.Capability.multiprotocol_ext(1, 1),
            Bgp.Protocol.Capability.asn4(state.options.local_as),
          ],
        }))
        {:noreply, %State{state | socket: socket}}
      {:error, _reason} ->
        Process.send(self(), :connect, [])
        {:noreply, state}
    end
  end

  def handle_info(:keepalive, state) do
    Logger.info(fn -> "-> KEEPALIVE" end)
    if state.socket != nil, do:
      :gen_tcp.send(state.socket, Bgp.Protocol.keepalive())
    {:noreply, %State{state | keepalive_timer:
      Process.send_after(self(), :keepalive, trunc(state.holdtime / 3) * 1_000)
    }}
  end

  def handle_info(:send_route, state) do
    {:noreply, send_update(state)}
  end

  def handle_info({:tcp_error, _socket, _reason}, state) do
    :gen_tcp.close(state.socket)
    if state.keepalive_timer != nil, do:
      Process.cancel_timer(state.keepalive_timer)
    Process.send(self(), :connect, [])
    {:noreply, %State{options: state.options}}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    :gen_tcp.close(state.socket)
    if state.keepalive_timer != nil, do:
      Process.cancel_timer(state.keepalive_timer)
    Process.send(self(), :connect, [])
    {:noreply, %State{options: state.options}}
  end

  def handle_info({:tcp, _socket, data}, state) do
    state =
      case Bgp.Protocol.decode(state.msgtail <> data) do
        {:ok, msgs, tail} ->
          state = %State{state | msgtail: tail}
          Enum.reduce(msgs, state, fn(msg, state) ->
            message_dump(msg)
            handle_message(state, msg)
          end)
        {:error, notificationmsg} ->
          :gen_tcp.send(state.socket, notificationmsg)
          state
      end

    {:noreply, state}
  end

  @spec send_update(State.t) :: State.t
  defp send_update(state) do
    prefix = Bgp.Protocol.ip4_next(state.options.prefix_start, state.prefix_cur)
    <<prefix_address::32>> = <<
      elem(prefix, 0)::8,
      elem(prefix, 1)::8,
      elem(prefix, 2)::8,
      elem(prefix, 3)::8
    >>
    case :gen_tcp.send(state.socket, Bgp.Protocol.Update.encode(%Bgp.Protocol.Update.Route{
      pattrs: [
        Bgp.Protocol.Update.pattr_origin(0),
        Bgp.Protocol.Update.pattr_aspath(2, [state.options.local_as]),
        Bgp.Protocol.Update.pattr_nexthop(
          Bgp.Protocol.ip4_to_integer(state.options.local_address)),
      ],
      prefix: prefix_address,
      prefixlen: 32,
    })) do
      :ok ->
        state = %State{state | prefix_cur: state.prefix_cur + 1}
        if state.prefix_cur < state.options.prefix_amount do
          send_update(state)
        else
          state
        end
      {:error, _reason} ->
        Process.send(self(), :send_route, [])
        state
    end
  end

  @spec handle_message(State.t, Bgp.Protocol.Message.t) :: State.t
  defp handle_message(%State{bstate: :open_sent} = state, msg) do
    case msg.type do
      :open ->
        # BGP requires the first message after the OPEN to be a KEEPALIVE.
        Process.send(self(), :keepalive, [])
        Process.send(self(), :send_route, [])
        %State{state | bstate: :established, holdtime: msg.value.holdtime}

      _ ->
        state
    end
  end

  defp handle_message(%State{bstate: :established} = state, msg) do
    case msg.type do
      _ ->
        state
    end
  end

  #
  # Debug messages
  #
  defp message_dump(%Bgp.Protocol.Message{} = msg) do
    case msg.type do
      :open ->
        message_dump(msg.value)
      :update ->
        Logger.info(fn -> "<- UPDATE" end)
      :notification ->
        Logger.info(fn -> "<- NOTIFICATION" end)
      :keepalive ->
        Logger.info(fn -> "<- KEEPALIVE" end)
      _ ->
        Logger.info(fn -> "<- UNKNOWN" end)
    end
  end

  defp message_dump(%Bgp.Protocol.Open.Message{} = msg) do
    Logger.info(fn ->
      Enum.reduce(msg.params,
        "<- OPEN: Version #{msg.version} | Remote ASN #{msg.remote_as} | " <>
        "Holdtime #{msg.holdtime} | Router ID #{msg.routerid} | " <>
        "params:\n", fn(param, acc) ->
          case param.type do
            2 -> acc <> "Capability type #{param.value.type}\n"
            _ -> acc <> "Unknown (#{param.type}) type\n"
          end
        end)
    end)
  end
end
