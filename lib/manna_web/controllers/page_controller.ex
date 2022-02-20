defmodule MannaWeb.PageController do
  use MannaWeb, :controller

  @table_name :numbers

  def index(conn, _params) do
    render(conn, "index.html")
  end

  defp gender("f"), do: "Donna"
  defp gender("m"), do: "Uomo"
  defp gender(""), do: ""
  defp gender(_), do: "0"

  def normalize(conn, %{"file" => %Plug.Upload{path: file_path}}) do

    converted = "/tmp/converted.csv"
    stream_file = File.stream!(converted, [:write])

    file_path
    |> File.stream!
    |> Stream.drop(1)
    |> Task.async_stream(fn line ->
      IO.inspect line
      [email, nome, sesso, _data_nascita, create_ip, create_ts, url | _] = String.split(line, ",")

      ["id0", create_ip, create_ts, email, gender(sesso) , nome , "", "0", "", "0", "", "", "#{url}\n" ]
      |> Enum.join(";")
    end)
    |> Stream.map(&elem(&1, 1))
    |> Stream.into(stream_file)
    |> Stream.run()

    conn
    |> put_resp_header("content-disposition", ~s(attachment; filename="converted.csv"))
    |> send_file(200, converted)
  end

  def process(conn, %{
    "add_file" => %Plug.Upload{path: add_file_path},
    "base_file" => %Plug.Upload{path: base_file_path}
    }) do

    :ets.new(@table_name, [:set, :public, :named_table])

    rows_added = "/tmp/rows_added.csv"
    {:ok, _file_db} = File.open(rows_added, [:write])

    base_file_path
    |> File.stream!
    |> Stream.drop(1)
    |> Task.async_stream(&get_number/1)
    |> Stream.run()

    IO.inspect length(:ets.tab2list(@table_name)), label: "ETS records inserted"

    add_file_path
    |> File.stream!
    |> Stream.drop(1)
    |> Task.async_stream(&filter_line/1)
    |> Stream.filter(&(not match?({:ok, nil}, &1)))
    |> Stream.map(&elem(&1,1))
    |> then(fn stream ->
      :ok = Stream.into(stream, File.stream!(rows_added, [:write])) |> Stream.run()
      :ok = Stream.into(stream, File.stream!(base_file_path, [:append])) |> Stream.run()

      :ets.delete(@table_name)

      files = [
        {'rows_added.csv', File.read!(rows_added)},
        {'file_db.csv', File.read!(base_file_path)}
      ]
      zip_filename = "file.zip"
      {:ok, _zip_file} = :zip.create(zip_filename, files)

      conn
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{zip_filename}"))
      |> send_file(200, zip_filename)
    end)

  end

  defp get_number(line) do
    num = line |> String.split(";") |> Enum.at(7)
    :ets.insert(:numbers, {num, 1})
  end

  defp filter_line(line) do
    line
    |> String.split(";")
    |> Enum.at(7)
    |> then(fn x ->
      Enum.empty?(:ets.lookup(@table_name, x))
    end)
    |> case do
      true  -> line
      false -> nil
    end
  end
end
