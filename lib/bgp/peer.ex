defmodule Bgp.Peer do
  @moduledoc """
  BGP peer handling library.
  """
  use GenServer
  require Logger

  defmodule Options do
    @enforce_keys [:neighbor, :remote_as, :local_address, :local_as, :router_id]
    defstruct neighbor: nil, neighbor_port: 179, remote_as: nil,
      local_address: nil, local_as: nil, router_id: nil

    @type t :: %Options{
      neighbor: :inet.ip4_address,
      neighbor_port: :inet.port_number,
      remote_as: Bgp.Protocol.as_number,
      local_address: :inet.ip4_address,
      local_as: Bgp.Protocol.as_number,
      router_id: Bgp.Protocol.router_id,
    }
  end

  defmodule State do
    @enforce_keys [:options]
    defstruct options: nil, socket: nil, bstate: :open_sent, msgtail: <<>>

    @type bgp_state :: :open_sent | :established
    @type t :: %State{
      options: Options.t,
      socket: port,
      bstate: bgp_state,
      msgtail: binary,
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

  def init(opts) do
    Process.send(self(), :connect, [])
    {:ok, %State{options: opts}}
  end

  def handle_info(:connect, state) do
    conn_opts = [active: :once, ip: state.options.local_address, mode: :binary]
    neighbor = state.options.neighbor
    port = state.options.neighbor_port
    case :gen_tcp.connect(neighbor, port, conn_opts) do
      {:ok, socket} ->
        :gen_tcp.send(socket, Bgp.Protocol.Open.encode(%Bgp.Protocol.Open.Options{
          bgpid: state.options.router_id,
          my_as: state.options.local_as,
          params: [
            Bgp.Protocol.Capability.multiprotocol_ext(1, 1),
            Bgp.Protocol.Capability.rr_cisco(),
            Bgp.Protocol.Capability.rr(),
            Bgp.Protocol.Capability.asn4(state.options.local_as),
            Bgp.Protocol.Capability.add_path(1, 1, 1),
            Bgp.Protocol.Capability.fqdn("bgpd", "local"),
            Bgp.Protocol.Capability.graceful_restart(120),
          ],
        }))
        {:noreply, %State{state | socket: socket}}
      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_info({:tcp_error, _socket, reason}, state) do
    {:stop, "error: #{reason}", state}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    {:stop, "connection closed", state}
  end

  def handle_info({:tcp, _socket, data}, state) do
    data = state.msgtail <> data

    state =
      case Bgp.Protocol.decode(data) do
        {:ok, msgs, tail} ->
          %State{state | msgtail: tail}
          Enum.reduce(msgs, state, fn(msg, state) ->
            message_dump(msg)
            handle_message(state, msg)
          end)
        {:error, notificationmsg} ->
          :gen_tcp.send(state.socket, notificationmsg)
          state
      end

    # Ask for one more message
    :inet.setopts(state.socket, active: :once)

    {:noreply, state}
  end

  @spec handle_message(State.t, Bgp.Protocol.Message.t) :: State.t
  defp handle_message(%State{bstate: :open_sent} = state, msg) do
    case msg.type do
      :open ->
        # BGP requires the first message after the OPEN to be a KEEPALIVE.
        Logger.info(fn -> "-> KEEPALIVE" end)
        :gen_tcp.send(state.socket, Bgp.Protocol.keepalive())
        %State{state | bstate: :established}

      _ ->
        state
    end
  end

  defp handle_message(%State{bstate: :established} = state, msg) do
    case msg.type do
      :keepalive ->
        Logger.info(fn -> "-> KEEPALIVE" end)
        :gen_tcp.send(state.socket, Bgp.Protocol.keepalive())
        %State{state | bstate: :established}

      _ ->
        Logger.info(fn -> "-> UPDATE 10.0.100.10/32 \"2\" IGP NEXTHOP \"10.0.2.2\"" end)
        <<paddr::32>> = <<10, 0, 100, 10>>
        :gen_tcp.send(state.socket, Bgp.Protocol.Update.encode(%Bgp.Protocol.Update.Route{
          pattrs: [
            Bgp.Protocol.Update.pattr_origin(0),
            Bgp.Protocol.Update.pattr_aspath(2, [state.options.local_as]),
            Bgp.Protocol.Update.pattr_nexthop(
              Bgp.Protocol.ip4_to_integer({10, 0, 2, 2})),
          ],
          prefix: paddr,
          prefixlen: 32,
        }))
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
