defmodule MannaWeb.Router do
  use MannaWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_root_layout, {MannaWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", MannaWeb do
    pipe_through :browser

    get "/", PageController, :index
    post "/process", PageController, :process
    post "/normalize", PageController, :normalize
  end
end
