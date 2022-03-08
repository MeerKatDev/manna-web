defmodule MannaWeb.PageController do
  use MannaWeb, :controller

  @table_name :numbers

  # must keep order
  @csv_fields [
    id: "Id",
    data_reg: "Data Reg",
    email: "Email",
    genere: "Genere",
    nome: "Nome",
    cognome: "Cognome",
    mobile: "Mobile",
    data_nascita: "Data di Nascita",
    cap: "CAP",
    citta: "Citta",
    provincia: "Provincia",
    url: "URL"
  ]

  def index(conn, _params) do
    render(conn, "index.html")
  end

  def md5_column(conn, %{"base_file" => %Plug.Upload{path: file_path}, "index" => index, "sep" => sep}) do
    result_file = "/tmp/result.csv"
    stream_file = File.stream!(result_file, [:write])

    {idx, ""} = Integer.parse(index)

    file_path
    |> File.stream!()
    |> Stream.drop(1)
    |> Task.async_stream(&column_to_md5(&1, idx, sep), max_concurrency: (System.schedulers_online() * 2))
    |> Stream.map(&elem(&1, 1))
    |> Stream.into(stream_file)
    |> Stream.run()

    conn
    |> put_resp_header("content-disposition", ~s(attachment; filename="result.csv"))
    |> send_file(200, result_file)

  end

  def normalize(conn, %{"file" => %Plug.Upload{path: file_path}, "column" => cols, "sep" => sep}) do

    IO.inspect System.schedulers_online(), label: "Online schedulers"

    converted = "/tmp/converted.csv"
    stream_file = File.stream!(converted, [:write])

    file_path
    |> File.stream!()
    |> Stream.drop(1)
    |> Task.async_stream(&convert_columns(&1, cols, sep), max_concurrency: (System.schedulers_online() * 2))
    |> Stream.map(&elem(&1, 1))
    |> Stream.into(stream_file)
    |> Stream.run()

    conn
    |> put_resp_header("content-disposition", ~s(attachment; filename="converted.csv"))
    |> send_file(200, converted)
  end

  def process(conn, %{
        "add_file" => %Plug.Upload{path: add_file_path},
        "base_file" => %Plug.Upload{path: base_file_path},
        "index_dedup" => index,
        "base_sep" => base_sep,
        "add_sep" => add_sep,
      }) do
    :ets.new(@table_name, [:set, :public, :named_table])

    IO.inspect System.schedulers_online(), label: "Online schedulers"

    {idx, ""} = Integer.parse(index)

    rows_added = "/tmp/rows_added.csv"
    {:ok, _file_db} = File.open(rows_added, [:write])

    base_file_path
    |> File.stream!()
    |> Stream.drop(1)
    |> Task.async_stream(&get_number(&1, idx, base_sep))
    |> Stream.run()

    IO.inspect(length(:ets.tab2list(@table_name)), label: "ETS records inserted")

    add_file_path
    |> File.stream!()
    |> Stream.drop(1)
    |> Task.async_stream(&filter_line(&1, idx, add_sep), max_concurrency: (System.schedulers_online() * 2))
    |> Stream.filter(&(not match?({:ok, nil}, &1)))
    |> Stream.map(&elem(&1, 1))
    |> then(fn stream ->
      :ok = Stream.into(stream, File.stream!(rows_added, [:write])) |> Stream.run()
      :ok = Stream.into(stream, File.stream!(base_file_path, [:append])) |> Stream.run()

      true = :ets.delete(@table_name)

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

  defp gender("f"), do: "Donna"
  defp gender("m"), do: "Uomo"
  defp gender("ND"), do: "ND"
  defp gender(g), do: g

  defp convert_columns(line, cols, sep) do
    @csv_fields
    |> Keyword.keys()
    |> Enum.map(fn label ->
      cols
      |> Map.get(to_string(label))
      |> Integer.parse()
      |> case do
        {idx, ""} ->
          line
          |> String.split(sep)
          |> Enum.at(idx)
          |> String.trim

        :error    -> "ND"
      end
    end)
    |> List.update_at(3, &gender/1)
    |> List.update_at(-1, &"#{&1}\n")
    |> Enum.join(sep)
  end

  defp get_number(line, idx, sep) do
    field = line |> String.split(sep) |> Enum.at(idx)
    true = :ets.insert(@table_name, {field, 1})
  end

  defp column_to_md5(line, idx, sep) do
    field = line |> String.split(sep) |> Enum.at(idx)
    md5ed_fields = :crypto.hash(:md5 , field) |> Base.encode16()
    String.trim(line)
    |> String.ends_with?(sep)
    |> if do
      line <> md5ed_fields <> sep
    else
      line <> sep <> md5ed_fields
    end
  end

  defp filter_line(line, idx, sep) do
    line
    |> String.split(sep)
    |> Enum.at(idx)
    |> then(fn x ->
      Enum.empty?(:ets.lookup(@table_name, x))
    end)
    |> case do
      true -> line
      false -> nil
    end
  end
end
