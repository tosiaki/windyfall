import Config

import_config "dev.secret.exs"

# Configure your database
config :windyfall, Windyfall.Repo,
  username: "postgres",
  hostname: "localhost",
  database: "windyfall_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :windyfall, :debug_features, true

# Find node executable (usually just 'node' works if in PATH)
node_executable = System.find_executable("node") || "node"
# Construct the likely path to npm-cli.js relative to node's dir
# This assumes a standard installation structure. Adjust if needed.
node_dir = Path.dirname(node_executable)
npm_cli_path = Path.join([node_dir, "node_modules", "npm", "bin", "npm-cli.js"])

# For development, we disable any cache and enable
# debugging and code reloading.
#
# The watchers configuration can be used to run external
# watchers to your application. For example, we can use it
# to bundle .js and .css sources.
config :windyfall, WindyfallWeb.Endpoint,
  # Binding to loopback ipv4 address prevents access from other machines.
  # Change to `ip: {0, 0, 0, 0}` to allow access from other machines.
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "1/o3mYwJmxHfoWH4ZdSXJMwXOEIjlyrh8nFGYQDjDfeRBfYmx7DC+TVbWKfry67g",
  watchers: [
    tailwind: {Tailwind, :install_and_run, [:windyfall, ~w(--watch)]},
    node: [
      "build.js", # The script to run
      "--watch",  # The flag to enable watch mode in your build.js
      cd: Path.expand("../assets", __DIR__) # Execute from the assets directory
    ],
  ]

# ## SSL Support
#
# In order to use HTTPS in development, a self-signed
# certificate can be generated by running the following
# Mix task:
#
#     mix phx.gen.cert
#
# Run `mix help phx.gen.cert` for more information.
#
# The `http:` config above can be replaced with:
#
#     https: [
#       port: 4001,
#       cipher_suite: :strong,
#       keyfile: "priv/cert/selfsigned_key.pem",
#       certfile: "priv/cert/selfsigned.pem"
#     ],
#
# If desired, both `http:` and `https:` keys can be
# configured to run both http and https servers on
# different ports.

# Watch static and templates for browser reloading.
config :windyfall, WindyfallWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*(po)$",
      ~r"lib/windyfall_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :windyfall, dev_routes: true

config :windyfall, WindyfallWeb.Endpoint,
  static_uploads: "priv/static/uploads"

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

# Set a higher stacktrace during development. Avoid configuring such
# in production as building large stacktraces may be expensive.
config :phoenix, :stacktrace_depth, 20

# Initialize plugs at runtime for faster development compilation
config :phoenix, :plug_init_mode, :runtime

# Include HEEx debug annotations as HTML comments in rendered markup
config :phoenix_live_view, :debug_heex_annotations, true

# Disable swoosh api client as it is only required for production adapters.
config :swoosh, :api_client, false
