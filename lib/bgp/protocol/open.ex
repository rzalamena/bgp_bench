defmodule Bgp.Protocol.Open do
  defmodule Options do
    @enforce_keys [:bgpid, :my_as]
    defstruct version: 4, holdtime: 30, bgpid: nil, my_as: nil,
              paramslen: 0, params: <<>>

    @type version :: 0..255
    @type holdtime :: 0..65535
    @type paramslen :: 0..255
    @type t :: %Options{
      version: version,
      holdtime: holdtime,
      bgpid: Bgp.Protocol.router_id,
      params: list(binary),
    }
  end

  defmodule Param do
    @enforce_keys [:type, :value]
    defstruct [type: nil, value: %{}]

    @type param_type :: 0..255
    @type t :: %Param{
      type: param_type,
      value: any,
    }
  end

  @doc """
  OPEN Message Format:
  * Version: 1 byte unsigned integer. Current version is 4.
  * My Autonomous System: 2 bytes.
  * Hold Time: 2 byte unsigned integer. Maximum time in seconds to receive
    keepalive.
  * BGP Identifier: 4 bytes unsigned integer. Router identification.
  * Optional Parameters len: 1 byte.
  * Parameters: 0 or more bytes.
  """
  @spec encode(Options.t) :: binary
  def encode(%Options{} = open_opts) do
    params = Enum.reduce(open_opts.params, <<>>, fn(param, acc) ->
      acc <> param
    end)
    open_header = <<
      open_opts.version::8,
      open_opts.my_as::16,
      open_opts.holdtime::16,
      open_opts.bgpid::32,
      byte_size(params)::8,
      params::binary
    >>
    Bgp.Protocol.message_header(byte_size(open_header), 1) <> open_header
  end

  @spec decode_params(binary, list(Param.t)) :: {:ok, list(Param.t)} | :error
  defp decode_params(<<type::8, length::8, data::binary>>, acc) do
    # Extract param value and point tail to next param
    <<value::bytes-size(length), tail::binary>> = data

    # Store param and go to the next one
    case type do
      2 -> # Capability (RFC 4271)
        case Bgp.Protocol.Capability.decode(data) do
          {:ok, cap} ->
            decode_params(tail, [%Param{type: type, value: cap} | acc])
          :error ->
            decode_params(tail, [%Param{type: type, value: value} | acc])
        end
      _ -> # Unhandled
        decode_params(tail, [%Param{type: type, value: value} | acc])
    end
  end
  defp decode_params(<<>>, acc), do: {:ok, acc}
  defp decode_params(_, _), do: :error
  def decode_params(data), do: decode_params(data, [])
end
