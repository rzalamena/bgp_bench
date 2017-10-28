defmodule Bgp.Protocol.Update do
  @moduledoc """
  Documentation for protocol UPDATE messages (RFC 4271).
  """
  use Bitwise

  defmodule PathAttribute do
    @moduledoc """
    Path attribute options for encoding.
    """
    @enforce_keys [:type, :flags, :value]
    defstruct [type: nil, flags: nil, value: nil]

    @type pattr_type :: 0..255
    @type pattr_flag :: :optional | :transitive | :partial | :extended
    @type t :: %PathAttribute{
      type: pattr_type,
      flags: list(pattr_flag),
      value: binary,
    }
  end

  defmodule Route do
    @moduledoc """
    Route definition for encoding.
    """
    @enforce_keys [:prefix, :prefixlen]
    defstruct [pattrs: [], prefix: nil, prefixlen: nil]

    @type prefix_length :: 0..128
    @type t :: %Route{
      pattrs: list(binary),
      prefix: non_neg_integer,
      prefixlen: prefix_length,
    }
  end

  @spec pattr_encode(PathAttribute.t) :: binary
  defp pattr_encode(%PathAttribute{} = pattr) do
    length = byte_size(pattr.value)
    flags = 0

    flags =
      if :optional in pattr.flags do
        bor(flags, bsr(1, 7))
      else
        flags
      end

    # Must set transitive in case of non-optional
    # TODO fix me
    flags =
      if :transitive in pattr.flags do
        flags ||| (1 <<< 6)
      else
        flags
      end

    # Non optional or optional non transitive, this must be zero
    # TODO fix me
    flags =
      if :partial in pattr.flags do
        bor(flags, bsr(1, 6))
      else
        flags
      end

    # Extended flag means length will have two bytes, otherwise one.
    if :extended in pattr.flags do
      flags = bor(flags, bsr(1, 6))
      <<flags::8, pattr.type::8, length::16, pattr.value::binary>>
    else
      <<flags::8, pattr.type::8, length::8, pattr.value::binary>>
    end
  end

  @doc """
  Mandatory update path attribute.

  Origin type values might be:
  0: IGP
  1: EGP
  2: Incomplete
  """
  @spec pattr_origin(non_neg_integer) :: binary
  def pattr_origin(type), do:
    pattr_encode(%PathAttribute{
      type: 1, # Origin
      flags: [:transitive],
      value: <<type::8>>, # Origin type
    })

  @doc """
  Mandatory update path attribute.

  AS PATH type values might be:
  1: AS_SET: unordered set of ASes a route in the UPDATE message has traversed
  2: AS_SEQUENCE: ordered set of ASes a route in the UPDATE message has traversed
  """
  @spec pattr_aspath(non_neg_integer, list(non_neg_integer)) :: binary
  def pattr_aspath(type, as) do
    asnum = Enum.count(as)
    ases = Enum.reduce(as, <<>>, fn(as, acc) ->
      acc <> <<as::32>>
    end)

    pattr_encode(%PathAttribute{
      type: 2, # AS PATH
      flags: [:transitive],
      value: <<type::8, asnum::8, ases::binary>>, # AS Path data
    })
  end

  @doc """
  Mandatory update path attribute.

  Nexthop is the address of the nexthop neighbor.

  TODO: support IPv6.
  """
  @spec pattr_nexthop(non_neg_integer) :: binary
  def pattr_nexthop(nexthop), do:
    pattr_encode(%PathAttribute{
      type: 3, # NEXTHOP
      flags: [:transitive],
      value: <<nexthop::32>>, # AS Path data
    })

  @doc """
  Encodes a route into an UPDATE message ready to be sent.
  """
  @spec encode(Route.t) :: binary
  def encode(%Route{} = route) do
    pattrs = Enum.reduce(route.pattrs, <<>>, fn(pattr, acc) ->
      acc <> pattr
    end)
    pattrslen = byte_size(pattrs)
    # TODO handle withdrawn
    withdrawlen = 0
    withdraws = <<>>

    update_header = <<
      withdrawlen::16,
      withdraws::binary,
      pattrslen::16,
      pattrs::binary,
      route.prefixlen::8,
      route.prefix::32, # TODO support IPv6
    >>
    Bgp.Protocol.message_header(byte_size(update_header), 2) <> update_header
  end
end
