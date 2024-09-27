defmodule VintageNetSocketCAN do
  @moduledoc """
  Support for SocketCAN interfaces
  """

  @behaviour VintageNet.Technology

  alias VintageNet.Interface.RawConfig
  require Logger

  @required_options [
    {:bitrate, :integer}
  ]

  @impl VintageNet.Technology
  def normalize(%{type: __MODULE__} = config) do
    normalized = Map.get(config, :vintage_net_socket_can)

    # check the options to ensure they are the right type and present
    for {key, type} <- @required_options do
      case({normalized[key], type}) do
        {value, :integer} when is_integer(value) -> :ok
        {value, :float} when is_float(value) -> :ok
        {value, :boolean} when is_boolean(value) -> :ok
        _ -> raise ArgumentError, "#{type} key :#{key} is required"
      end
    end

    Logger.debug("settings are: #{inspect(normalized)}")
    %{type: __MODULE__, vintage_net_socket_can: normalized}
  end

  @impl VintageNet.Technology
  def to_raw_config(ifname, %{type: __MODULE__} = config, _opts) do
    normalized_config = Map.get(config, :vintage_net_socket_can, %{})
    up_cmds = up_cmds(ifname, normalized_config)

    Logger.debug("up commands are: #{inspect(up_cmds)}")

    %RawConfig{
      ifname: ifname,
      type: __MODULE__,
      source_config: config,
      required_ifnames: [],
      child_specs: [{VintageNet.Connectivity.LANChecker, ifname}],
      up_cmds: up_cmds,
      up_cmd_millis: 5_000,
      down_cmds: [
        {:run_ignore_errors, "ip", ["addr", "flush", "dev", ifname, "label", ifname]},
        {:run, "ip", ["link", "set", ifname, "down"]}
      ]
    }
  end

  defp up_cmds(ifname, config) do
    maybe_add_interface(ifname)
    |> add_run_ip_config_command(ifname, config)
    |> maybe_add_ifconfig_cmd(ifname, config[:txqueuelen])
    |> add_ip_up_cmd(ifname)
  end

  defp add_run_ip_config_command(commands, ifname, config) do
    commands ++
      [
        run_ip_config_command(ifname, config)
      ]
  end

  defp run_ip_config_command(ifname, config) do
    parameter =
      ip_default_parameter(ifname, config)
      |> ip_maybe_add_sample_point(config[:sample_point])
      |> ip_maybe_add_loopback(config[:loopback])
      |> ip_maybe_add_listen_only(config[:listen_only])

    {:run, "ip", parameter}
  end

  defp ip_default_parameter(ifname, config) do
    [
      "link",
      "set",
      ifname,
      "type",
      "can",
      "bitrate",
      Integer.to_string(config[:bitrate])
    ]
  end

  def ip_maybe_add_sample_point(current_params, sample_point) do
    if is_float(sample_point) do
      current_params ++
        [
          "sample-point",
          Float.to_string(sample_point)
        ]
    else
      current_params
    end
  end

  def ip_maybe_add_loopback(current_params, loopback) do
    if is_boolean(loopback) do
      current_params ++
        [
          "loopback",
          if(loopback, do: "on", else: "off")
        ]
    else
      current_params
    end
  end

  def maybe_add_ifconfig_cmd(current_commands, ifname, txqueuelen) do
    if is_integer(txqueuelen) do
      current_commands ++
        [
          {:run, "ifconfig", [ifname, "txqueuelen", Integer.to_string(txqueuelen)]}
        ]
    else
      current_commands
    end
  end

  def add_ip_up_cmd(current_commands, ifname) do
    current_commands ++
      [
        {:run, "ip", ["link", "set", ifname, "up"]}
      ]
  end

  def ip_maybe_add_listen_only(current_params, listen_only) do
    if is_boolean(listen_only) do
      current_params ++
        [
          "listen-only",
          if(listen_only, do: "on", else: "off")
        ]
    else
      current_params
    end
  end

  defp maybe_add_interface(ifname) do
    case System.cmd("ip", ["link", "show", ifname]) do
      {_, 0} -> []
      _ -> [{:run_ignore_errors, "ip", ["link", "add", ifname, "type", "can"]}]
    end
  end
end
