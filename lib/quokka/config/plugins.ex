# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Config.Plugins do
  @moduledoc false

  require Logger

  def load(quokka_config) do
    load_required_files(quokka_config[:requires] || [])
    parse_plugins(quokka_config[:plugins] || [])
  end

  defp load_required_files(patterns) do
    patterns
    |> List.wrap()
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.each(fn path ->
      if File.exists?(path) do
        Code.require_file(path)
      else
        Logger.warning("Quokka plugin file not found: #{path}")
      end
    end)
  end

  defp parse_plugins(plugin_specs) do
    {modules, module_opts} =
      Enum.reduce(plugin_specs, {[], %{}}, fn spec, {modules, opts_map} = acc ->
        {module, opts} = normalize_plugin_spec(spec)

        case Quokka.Plugin.validate(module) do
          {:ok, module} ->
            {[module | modules], Map.put(opts_map, module, opts)}

          {:error, reason} ->
            Logger.warning("Invalid Quokka plugin:\n\n#{inspect(reason)}")
            acc
        end
      end)

    {Enum.reverse(modules), module_opts}
  end

  defp normalize_plugin_spec({module, opts}) when is_atom(module) and is_list(opts), do: {module, opts}
  defp normalize_plugin_spec(module) when is_atom(module), do: {module, []}
end
