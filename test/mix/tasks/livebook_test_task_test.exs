defmodule Mix.Tasks.Livebook.TestTaskTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Livebook.Test.LivemdExtract

  defp livemd(cells) do
    Enum.map_join(cells, "\n\n", &("```elixir\n" <> &1 <> "\n```"))
  end

  @tag :tmp_dir
  test "cells run one at a time, so a later cell can use a struct defined at runtime",
       %{tmp_dir: tmp_dir} do
    # Compiled at runtime by cell 1, the way Mix.install/2 loads a package.
    # Expanding the whole notebook up front fails on %LivebookCellStruct{}.
    script =
      LivemdExtract.to_elixir_script(
        livemd([
          ~s|Code.compile_string("defmodule LivebookCellStruct do defstruct [:a] end")|,
          ~s|alias LivebookCellStruct, as: S\nvalue = %S{a: 41}|,
          ~s|%S{a: a} = value\nIO.puts("answer=" <> to_string(a + 1))|
        ])
      )

    path = Path.join(tmp_dir, "notebook.exs")
    File.write!(path, script)

    assert {output, 0} = System.cmd("elixir", [path], stderr_to_stdout: true)
    assert output =~ "answer=42"
  end

  @tag :tmp_dir
  test "a failing cell is named in the output", %{tmp_dir: tmp_dir} do
    script = LivemdExtract.to_elixir_script(livemd(["x = 1", "raise \"boom\""]))
    path = Path.join(tmp_dir, "failing.exs")
    File.write!(path, script)

    assert {output, status} = System.cmd("elixir", [path], stderr_to_stdout: true)
    assert status != 0
    assert output =~ "livebook cell 2 failed"
  end

  test "--local points the Hex ex_zarr dependency at this checkout" do
    cell = ~s|Mix.install([\n  {:ex_zarr, "~> 1.3"},\n  {:nx, "~> 0.7"}\n])|
    root = File.cwd!()

    assert LivemdExtract.to_elixir_script(livemd([cell]), local: true) =~
             inspect(~s|{:ex_zarr, path: "#{root}"}|) |> String.slice(1..-2//1)

    assert LivemdExtract.to_elixir_script(livemd([cell])) =~ ~s|{:ex_zarr, \\"~> 1.3\\"}|
  end
end
