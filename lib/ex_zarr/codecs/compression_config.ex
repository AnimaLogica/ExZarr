defmodule ExZarr.Codecs.CompressionConfig do
  @moduledoc """
  Configuration helper for compression library paths.

  Automatically detects library paths based on the platform and supports
  environment variable overrides for custom installations.

  ## Environment Variables

  You can override the automatic detection by setting these environment variables:

  - `COMPRESSION_LIB_DIRS` - Colon-separated list of library directories
  - `COMPRESSION_INCLUDE_DIRS` - Colon-separated list of header include directories
  - `HOMEBREW_PREFIX` - Override Homebrew installation path (macOS only)

  ## Examples

      # Get library directories for linking
      ExZarr.Codecs.CompressionConfig.library_dirs()
      # => ["/opt/homebrew/opt/zstd/lib", "/opt/homebrew/opt/lz4/lib", ...]

      # Get include directories for C headers (needed by Livebook.app / GUI PATH)
      ExZarr.Codecs.CompressionConfig.include_dirs()
      # => ["/opt/homebrew/opt/zstd/include", "/opt/homebrew/opt/lz4/include", ...]

      # Get library paths for runtime (rpaths)
      ExZarr.Codecs.CompressionConfig.rpath_dirs()
      # => ["/opt/homebrew/opt/zstd/lib", "/opt/homebrew/opt/lz4/lib", ...]

      # Get static library path
      ExZarr.Codecs.CompressionConfig.bzip2_static_lib()
      # => "/opt/homebrew/opt/bzip2/lib/libbz2.a"

  ## Platform Support

  - **macOS (ARM)**: Uses `/opt/homebrew` prefix by default
  - **macOS (Intel)**: Uses `/usr/local` prefix by default
  - **Linux**: Uses standard system library paths
  - **Custom**: Set `COMPRESSION_LIB_DIRS` / `COMPRESSION_INCLUDE_DIRS`
  """

  @compression_libs [:zstd, :lz4, :snappy, :"c-blosc", :bzip2]

  @doc """
  Returns the list of library directories to use for compilation linking.

  This is used by the Zig NIF compiler to find compression libraries.
  """
  def library_dirs do
    case System.get_env("COMPRESSION_LIB_DIRS") do
      nil -> detect_library_dirs()
      paths -> split_path_list(paths)
    end
  end

  @doc """
  Returns the list of include directories for compression C headers.

  Required so Zig `@cImport` / translate-c can find Homebrew headers when
  `pkg-config` is unavailable (common for Livebook.app with a minimal PATH).
  """
  def include_dirs do
    case System.get_env("COMPRESSION_INCLUDE_DIRS") do
      nil -> detect_include_dirs()
      paths -> split_path_list(paths)
    end
  end

  @doc """
  Returns the list of library directories to use for runtime rpaths.

  This is used by the Mix task to add rpaths to the compiled NIF.
  Includes both ARM and Intel Homebrew paths on macOS for maximum compatibility.
  """
  def rpath_dirs do
    case System.get_env("COMPRESSION_LIB_DIRS") do
      nil -> detect_rpath_dirs()
      paths -> split_path_list(paths)
    end
  end

  @doc """
  Returns the path to the bzip2 static library.

  Bzip2 only provides a static library on many systems, so we need the full path.
  """
  def bzip2_static_lib do
    case System.get_env("BZIP2_STATIC_LIB") do
      nil ->
        prefix = homebrew_prefix()
        "#{prefix}/opt/bzip2/lib/libbz2.a"

      path ->
        path
    end
  end

  @doc """
  Returns the Homebrew prefix path.

  Detects automatically based on platform, or uses HOMEBREW_PREFIX env var.
  """
  def homebrew_prefix do
    case System.get_env("HOMEBREW_PREFIX") do
      nil -> detect_homebrew_prefix()
      prefix -> prefix
    end
  end

  # Private functions

  # Unix uses ':' ; Windows uses ';' so drive letters like C: are preserved.
  defp split_path_list(paths) do
    sep =
      case :os.type() do
        {:win32, _} -> ";"
        _ -> ":"
      end

    paths
    |> String.split(sep)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp detect_library_dirs do
    case :os.type() do
      {:unix, :darwin} ->
        # macOS - use Homebrew
        prefix = detect_homebrew_prefix()
        build_lib_paths(prefix)

      {:unix, _} ->
        # Linux - use standard system paths
        # The linker will find these automatically, but we can specify common locations
        [
          "/usr/lib",
          "/usr/local/lib",
          "/usr/lib/x86_64-linux-gnu",
          "/usr/lib/aarch64-linux-gnu"
        ]
        |> Enum.filter(&File.dir?/1)

      _ ->
        []
    end
  end

  defp detect_include_dirs do
    case :os.type() do
      {:unix, :darwin} ->
        prefix = detect_homebrew_prefix()
        build_include_paths(prefix)

      {:unix, _} ->
        [
          "/usr/include",
          "/usr/local/include"
        ]
        |> Enum.filter(&File.dir?/1)

      _ ->
        []
    end
  end

  defp detect_rpath_dirs do
    case :os.type() do
      {:unix, :darwin} ->
        # macOS - include both ARM and Intel paths for compatibility
        arm_paths = build_lib_paths("/opt/homebrew")
        intel_paths = build_lib_paths("/usr/local")
        arm_paths ++ intel_paths

      {:unix, _} ->
        # Linux doesn't need rpaths - uses standard library paths
        []

      _ ->
        []
    end
  end

  defp detect_homebrew_prefix do
    # Prefer env / known brew binaries so Livebook.app (minimal PATH) still works
    brew_bins = [
      System.find_executable("brew"),
      "/opt/homebrew/bin/brew",
      "/usr/local/bin/brew"
    ]

    brew_bins
    |> Enum.find(&(&1 && File.regular?(&1)))
    |> case do
      nil ->
        architecture_homebrew_prefix()

      brew ->
        case System.cmd(brew, ["--prefix"], stderr_to_stdout: true) do
          {prefix, 0} -> String.trim(prefix)
          _ -> architecture_homebrew_prefix()
        end
    end
  rescue
    _ -> architecture_homebrew_prefix()
  end

  defp architecture_homebrew_prefix do
    case :erlang.system_info(:system_architecture) do
      arch when is_list(arch) ->
        arch_str = List.to_string(arch)

        if String.contains?(arch_str, "aarch64") or String.contains?(arch_str, "arm64") do
          "/opt/homebrew"
        else
          "/usr/local"
        end

      _ ->
        "/opt/homebrew"
    end
  end

  defp build_lib_paths(prefix) do
    Enum.map(@compression_libs, fn lib ->
      "#{prefix}/opt/#{lib}/lib"
    end)
  end

  defp build_include_paths(prefix) do
    @compression_libs
    |> Enum.map(fn lib -> "#{prefix}/opt/#{lib}/include" end)
    |> Enum.filter(&File.dir?/1)
  end
end
