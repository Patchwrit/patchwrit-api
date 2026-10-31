defmodule PatchwritApiWeb.Router do
  use PatchwritApiWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PatchwritApiWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :test_machines do
    plug PatchwritApiWeb.Plugs.RequireTestMachines
  end

  scope "/api/v1", PatchwritApiWeb do
    pipe_through :api

    post "/worker-callbacks/:id", WorkerCallbackController, :create
  end

  scope "/api/v1", PatchwritApiWeb do
    pipe_through [:api, :test_machines]

    post "/test-machines", TestMachineController, :create
    get "/test-machines", TestMachineController, :index
    get "/test-machines/:id", TestMachineController, :show
    post "/test-machines/:id/start", TestMachineController, :start
    post "/test-machines/:id/stop", TestMachineController, :stop
    delete "/test-machines/:id", TestMachineController, :delete
  end

  scope "/", PatchwritApiWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/analyses", AnalysisLive.Index
    live "/analyses/:id", AnalysisLive.Show, :overview
    live "/analyses/:id/findings", AnalysisLive.Show, :findings
    live "/analyses/:id/findings/:finding_id", AnalysisLive.Show, :finding
    live "/analyses/:id/dependencies", AnalysisLive.Show, :dependencies
    live "/analyses/:id/audit", AnalysisLive.Show, :audit
    get "/analyses/:id/sbom", SbomController, :download
    live "/repositories", RepositoryLive.Index
    live "/repositories/:id", RepositoryLive.Show
  end

  # Other scopes may use custom stacks.
  # scope "/api", PatchwritApiWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:patchwrit_api, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PatchwritApiWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
