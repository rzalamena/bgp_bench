defmodule Bgp.Protocol.Capability do
  defmodule Capability do
    @enforce_keys [:type, :value]
    defstruct [:type, :value]

    @type capability_type :: 0..255
    @type t :: %Capability{
      type: capability_type,
      value: binary,
    }
  end

  @doc """
  Encode capability into data.
  """
  @spec encode(Capability.t) :: binary
  def encode(%Capability{} = cap) do
    capdata = <<cap.type::8, byte_size(cap.value)::8, cap.value::binary>>
    <<
      2::8, # param type: capability (2)
      byte_size(capdata)::8, # param length
      capdata::binary # param data
    >>
  end

  @doc """
  Encode multiprotocol capability into data (RFC 4760).
  """
  @spec multiprotocol_ext(non_neg_integer, non_neg_integer) :: binary
  def multiprotocol_ext(afi, safi), do:
    encode(%Capability{
      type: 1,
      value: <<
        afi::16,
        0::8, # Reserved
        safi::8,
      >>,
    })

  @doc """
  Encode Cisco Route Refresh (RFC 7313).
  """
  @spec rr_cisco() :: binary
  def rr_cisco(), do:
    encode(%Capability{
      type: 128,
      value: <<>>,
    })

  @doc """
  Encode Route Refresh (RFC 7313).
  """
  @spec rr() :: binary
  def rr(), do:
    encode(%Capability{
      type: 2,
      value: <<>>,
    })

  @doc """
  Encode 4 byte ASN support and set the 4 byte ASN number (RFC 6793).
  """
  @spec asn4(non_neg_integer) :: binary
  def asn4(asn), do:
    encode(%Capability{
      type: 65,
      value: <<asn::32>>,
    })

  @doc """
  Encode add-path capability (RFC 7911).
  """
  @spec add_path(non_neg_integer, non_neg_integer, non_neg_integer) :: binary
  def add_path(afi, safi, sendreceive), do:
    encode(%Capability{
      type: 69,
      value: <<
        afi::16,
        safi::8,
        sendreceive::8,
      >>,
    })

  @doc """
  Encode FQDN capability (RFC Draft:
  https://tools.ietf.org/html/draft-walton-bgp-hostname-capability-02).
  """
  @spec fqdn(binary, binary) :: binary
  def fqdn(hostname, domain) do
    hostnamelen = byte_size(hostname)
    domainlen = byte_size(domain)
    encode(%Capability{
      type: 73,
      value: <<
        hostnamelen::8,
        hostname::binary,
        domainlen::8,
        domain::binary,
      >>,
    })
  end

  @doc """
  Encode Graceful restart capability (RFC 4724).
  """
  @spec graceful_restart(non_neg_integer) :: binary
  def graceful_restart(timer) do
    restart = 0
    encode(%Capability{
      type: 64,
      value: <<
        restart::1,
        0::3, # reserved
        timer::12,
      >>,
    })
  end

  @doc """
  Decode capability binary into Elixir data structure.
  """
  @spec decode(binary) :: {:ok, Capability.t} | :error
  def decode(<<type::8, length::8, data::binary>>) do
    <<value::bytes-size(length), _::binary>> = data
    {:ok, %Capability{type: type, value: value}}
  end
  def decode(_), do: :error
end
