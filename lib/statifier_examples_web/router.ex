defmodule StatifierExamplesWeb.Router do
  use StatifierExamplesWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {StatifierExamplesWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", StatifierExamplesWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/editor", EditorLive
    live "/plan", PlanLive
    live "/signup-screens", SignupScreensLive
    live "/signup-journey", SignupJourneyLive
  end

  # The BasicHTTP front: a location of a durable execution. No pipeline:
  # the request is a machine's POST, not a browser's, and every method
  # reaches the action so the front can answer 405 itself. The dispatch is
  # not logged: its path and params carry the location's token.
  scope "/basichttp", StatifierExamplesWeb do
    match :*, "/:token", BasicHTTPController, :event, log: false
  end

  # The card application form's front: a public form a visitor's browser
  # posts, urlencoded or JSON, on the JSON pipeline. No session and no
  # CSRF token: there is no signed-in visitor to protect, and the controller's
  # moduledoc says how a host guards the endpoint instead.
  scope "/form-post", StatifierExamplesWeb do
    pipe_through :api

    post "/card-applications", CardApplicationController, :create
  end

  # Other scopes may use custom stacks.
  # scope "/api", StatifierExamplesWeb do
  #   pipe_through :api
  # end
end
