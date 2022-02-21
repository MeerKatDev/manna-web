defmodule MannaWeb.PageView do
  use MannaWeb, :view

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

  defp csv_fields() do
    @csv_fields
  end
end
