defmodule WindyfallWeb.GameLive do
  use WindyfallWeb, :live_view

  alias WindyfallWeb.BuildItemComponent # Keep tooltip component
  alias Windyfall.Game.GameSessions
  alias WindyfallWeb.CoreComponents # For avatar path
  alias WindyfallWeb.DateTimeHelpers # For formatting if needed later
  import WindyfallWeb.TextHelpers, only: [pluralize: 3]


  @tick_interval 0.1
  @boost_multiplier 1.5 # Apply a 1.5x multiplier during boost
  @boost_recovery 15
  @boost_length 10

  # --- Keep existing game data maps (@buildings, @researches, @occupations) ---
  # (These maps remain unchanged from your original file)
  @buildings %{
    common_house: %{
      name: "Common house",
      cost: %{ wood: 15, stone: 10 },
      cost_scaling: 1.3,
      generation: %{ research: 0.3, gold: 0.2 },
      consume: %{ food: 1 },
      population: 1,
      require: MapSet.new([:housing])
    },
    farm: %{ name: "Farm", cost: %{ gold: 10, wood: 24 }, boost: %{ farmer: %{ food: 0.01 } }, farmer: 1, cost_scaling: 1.3, require: MapSet.new([:agriculture])},
    lumberjack_camp: %{ name: "Lumberjack camp", cost: %{ gold: 25, wood: 18 }, boost: %{ lumberjack: %{ wood: 0.01 } }, lumberjack: 1, cost_scaling: 1.4, require: MapSet.new([:wood_cutting])},
    quarry: %{ name: "Quarry", cost: %{ gold: 32, wood: 24, stone: 8 }, boost: %{ quarryman: %{ stone: 0.01 } }, quarryman: 1, cost_scaling: 1.375, require: MapSet.new([:stone_masonry])},
    mine: %{ name: "Mine", cost: %{ gold: 160, wood: 140, stone: 80 }, boost: %{ miner: %{ copper: 0.01, iron: 0.01 } }, cost_scaling: 1.4, require: MapSet.new([:mining])},
    artisan_workshop: %{ name: "Artisan workshop", cost: %{ gold: 150, wood: 120, stone: 80 }, boost: %{ lumberjack: %{ wood: 0.02 }, quarryman: %{ stone: 0.02 }, farmer: %{ food: 0.02 }, artisan: %{ tools: 0.02, gold: 0.02 } }, artisan: 1, cost_scaling: 1.4, require: MapSet.new([:pottery])},
    school: %{ name: "School", cost: %{ gold: 350, wood: 300, stone: 250, tools: 100 }, cost_scaling: 1.3, require: MapSet.new([:writing])},
    stable: %{ name: "Stable", cost: %{ gold: 500, wood: 500, tools: 250 }, boost: %{ farmer: %{ food: 0.02 } }, breeder: 1, cost_scaling: 1.3, require: MapSet.new([:breeding])},
    temple: %{ name: "Temple", cost: %{ gold: 1500, wood: 1000, stone: 1000, copper: 500, iron: 500, tools: 500 }, cost_scaling: 1.4, require: MapSet.new([:religion]), generation: %{ faith: 0.8 }},
    marketplace: %{ name: "Marketplace", cost: %{ gold: 1200, wood: 600, copper: 400, iron: 400, tools: 400 }, boost: %{ merchant: %{ gold: 0.02 }, artisan: %{ tools: 0.02, gold: 0.02 } }, merchant: 1, cost_scaling: 1.3, require: MapSet.new([:currency])},
    city_hall: %{ name: "City hall", cost: %{ gold: 1200, wood: 1000, stone: 750, copper: 400, iron: 400, tools: 150 }, population: 2, cost_scaling: 1.4, consume: %{ food: 1.5 }, require: MapSet.new([:municipal_administration])},
    magic_circle: %{ name: "Magic circle", cost: %{ stone: 2000, copper: 1000, faith: 700 }, cost_scaling: 1.4, require: MapSet.new([:magic]), generation: %{ mana: 1.5 }},
    city_center: %{ name: "City center", parts: 12, cost: %{ gold: 1500, wood: 750, stone: 750, copper: 500, iron: 250, tools: 25 }, boost: %{ all: %{ gold: 0.05, wood: 0.05, stone: 0.05, copper: 0.05, iron: 0.05, tools: 0.05 } }, cost_scaling: 1, require: MapSet.new([:end_ancient_era]), max: 1},
    fiefdom: %{ name: "Fiefdom", cost: %{ gold: 1500, wood: 1500, stone: 1000, copper: 500, iron: 500, tools: 500 }, boost: %{ farmer: %{ food: 0.03 }, breeder: %{ cow: 0.03, horse: 0.03 } }, farmer: 1, cost_scaling: 1.4, require: MapSet.new([:feudalism])},
    mansion: %{ name: "Mansion", cost: %{ gold: 4000, wood: 2000, stone: 1000, tools: 200, materials: 100 }, cost_scaling: 1.4, consume: %{ food: 3 }, population: 4, require: MapSet.new([:architecture])},
    carpenter_workshop: %{ name: "Carpenter workshop", cost: %{ gold: 1000, wood: 800, stone: 600, iron: 500, tools: 500 }, boost: %{ carpenter: %{ materials: 0.02 } }, carpenter: 1, cost_scaling: 1.4, require: MapSet.new([:architecture])},
    grocery: %{ name: "Grocery", cost: %{ gold: 1200, tools: 500, materials: 200 }, supplier: 1, boost: %{ supplier: %{ supplies: 0.02 } }, require: MapSet.new([:food_conservation]), cost_scaling: 1.4}
  }
  @researches %{
    housing: %{ name: "Housing" },
    agriculture: %{ name: "Agriculture", cost: %{ research: 10 }, require: [:housing]},
    stone_masonry: %{ name: "Stone masonry", cost: %{ research: 20 }, require: [:housing]},
    wood_cutting: %{ name: "Wood cutting", cost: %{ research: 20 }, require: [:housing]},
    mining: %{ name: "Mining", cost: %{ research: 250 }, building_require: %{ quarry: 3 }},
    crop_rotation: %{ name: "Crop rotation", cost: %{ research: 100 }, building_require: %{ farm: 5 }, boost: %{ farmer: %{ food: 0.05 } }},
    woodcarvers: %{ name: "Woodcarvers", cost: %{ research: 150, tools: 20 }, building_require: %{ lumberjack_camp: 5 }, boost: %{ lumberjack: %{ wood: 0.02 }}},
    stone_extraction_tools: %{ name: "Stone extraction tools", cost: %{ research: 175, tools: 25 }, building_require: %{ quarry: 5 }, boost: %{ quarryman: %{ stone: 0.02 }}},
    municipal_administration: %{ name: "Municipal administration", cost: %{ research: 2500}, building_require: %{ common_house: 15 }},
    storage: %{ name: "Storage", cost: %{ research: 300 }, require: [:agriculture]},
    breeding: %{ name: "Breeding", cost: %{ research: 800 }, require: [:storage], building_require: %{ farm: 5 }},
    pottery: %{ name: "Pottery", cost: %{ research: 150 }, require: [:stone_masonry]},
    archery: %{ name: "Archery", cost: %{ research: 200, wood: 150 }, require: [:wood_cutting]},
    writing: %{ name: "Writing", cost: %{ research: 500 }, require: [:pottery]},
    mythology: %{ name: "Mythology", cost: %{ research: 750 }, require: [:writing], building_require: %{ common_house: 8 }},
    religion: %{ name: "Religion", cost: %{ research: 3500, gold: 1500 }, require: [:writing]},
    mathematics: %{ name: "Mathematics", cost: %{ research: 2500 }, require: [:writing]},
    magic: %{ name: "Magic", cost: %{ faith: 750 }, require: [:religion]},
    currency: %{ name: "Currency", cost: %{ gold: 1500 }, require: [:mathematics]},
    bronze_working: %{ name: "Bronze working", cost: %{ research: 600, copper: 300 }, require: [:mining]},
    fortification: %{ name: "Fortification", cost: %{ research: 1000, wood: 1000, stone: 1000 }, require: [:bronze_working]},
    iron_working: %{ name: "Iron working", cost: %{ research: 5000, iron: 600 }, require: [:bronze_working]},
    servitude: %{ name: "Servitude", cost: %{ gold: 1250 }, require: [:bronze_working]},
    end_ancient_era: %{ name: "End ancient era", cost: %{ research: 5500 }, require: [:iron_working, :religion], building_require: %{ common_house: 15, artisan_workshop: 5 }},
    feudalism: %{ name: "Feudalism", cost: %{ research: 7500 }, building_require: %{ city_center: 1 }},
    architecture: %{ name: "Architecture", cost: %{ research: 8000, wood: 1500, stone: 1000 }, require: [:feudalism]},
    education: %{ name: "Education", cost: %{ research: 10000 }, require: [:feudalism]},
    food_conservation: %{ name: "Food conservation", cost: %{ research: 10000 }, require: [:education]},
    banking: %{ name: "Banking", cost: %{ research: 12000, gold: 8000 }, require: [:education]},
    metal_casting: %{ name: "Metal casting", cost: %{ research: 11500, iron: 1000 }, require: [:feudalism]},
    establish_boundaries: %{ name: "Establish boundaries", cost: %{ research: 12000, gold: 11000 }, require: [:architecture], boost: %{ all: %{ gold: 0.03, research: 0.03 }} }
  }
  @occupations %{
    farmer: %{ require: MapSet.new([:agriculture]), generation: %{ food: 1.6 }},
    lumberjack: %{ require: MapSet.new([:wood_cutting]), generation: %{ wood: 0.7 }},
    quarryman: %{ require: MapSet.new([:stone_masonry]), generation: %{ stone: 0.6 }},
    artisan: %{ require: MapSet.new([:pottery]), generation: %{ gold: 0.5, tools: 0.3 }},
    miner: %{ require: MapSet.new([:mining]), generation: %{ copper: 0.5, iron: 0.3 }},
    breeder: %{ require: MapSet.new([:breeding]), generation: %{ cow: 0.2, horse: 0.1 }},
    merchant: %{ require: MapSet.new([:currency]), generation: %{ gold: 3 }},
    carpenter: %{ require: MapSet.new([:architecture]), generation: %{ materials: 0.3 }, consume: %{ wood: 3, stone: 1.5, tools: 0.5 }},
    supplier: %{ require: MapSet.new([:food_conservation]), generation: %{ supplies: 0.4 }, consume: %{ food: 2, cow: 0.2 }}
  }
  @prayers %{ praise_gods: %{ cost: %{ faith: 250 } } }
  # --- End game data maps ---

  # Precompute resource names for iteration in template
  @resource_keys [
    :research, :gold, :food, :wood, :stone, :copper, :iron,
    :tin, :aluminum, # Added aluminum, tin (keep even if unused for now)
    :tools, :faith, :cow, :horse, :mana, :materials, :supplies # Added supplies
    # Removed firewood as it's handled separately/was for debugging
  ]

  def researches, do: @researches
  def buildings, do: @buildings
  def occupations, do: @occupations

  @debug_enabled Application.compile_env(:windyfall, :debug_features, false) || Mix.env() == :dev # Check config or Mix env

  def mount(_params, session, socket) do
    game_session = "#{session["game_session"]}"
    # Fetch initial state or create defaults
    game_state = GameSessions.get_session(game_session) || %{"score" => 0, "player_name" => "Guest #{Windyfall.Accounts.Guest.new_id()}"}

    initial_score = Map.get(game_state, "score", Map.get(game_state, "flow", 0))

    initial_resources = Map.new(@resource_keys, fn resource ->
      {resource, Map.get(game_state, Atom.to_string(resource), 0.0)}
    end)

    initial_resources = Map.new(@resource_keys, fn resource ->
      {resource, Map.get(game_state, Atom.to_string(resource), 0.0)} # Load from saved state or default to 0
    end)

    initial_buildings = Map.new(Map.keys(@buildings), fn building_name ->
      {building_name, Map.get(game_state, "building_#{building_name}", 0)} # Load from saved state
    end)

    initial_occupations = Map.new(Map.keys(@occupations), fn occupation ->
      {occupation, Map.get(game_state, "occupation_#{occupation}", 0)} # Load from saved state
    end)

    researches_done = MapSet.new(Map.get(game_state, "researches_done", []) |> Enum.map(&String.to_existing_atom/1))

    next_costs = Map.new(Map.keys(@buildings), fn building_name ->
      {building_name, building_cost(building_name, initial_buildings[building_name])}
    end)

    initial_deltas = Map.new(@resource_keys, fn k -> {k, 0.0} end)

    socket =
      socket
      |> assign(:game_session, game_session)
      |> assign(:player_name, Map.get(game_state, "player_name", "Guest #{Windyfall.Accounts.Guest.new_id()}")) # Add default here too
      |> assign(:score, initial_score) # Use the loaded/defaulted score
      |> assign(:resources, initial_resources)
      |> assign(:buildings, initial_buildings)
      |> assign(:occupations, initial_occupations)
      |> assign(:building_progress, %{}) # Reset progress on load, or load if saved
      |> assign(:researches_done, researches_done)
      |> assign(:next_costs, next_costs)
      |> assign(:deltas, initial_deltas)
      |> assign(:boosts, Map.get(game_state, "boosts", 5))
      |> assign(:boosting, Map.get(game_state, "boosting", false))
      |> assign(:boost_timer, Map.get(game_state, "boost_timer", 0))
      |> assign(:boost_recovery_time, Map.get(game_state, "boost_recovery_time", @boost_recovery))
      |> assign(:all_sessions, []) # Fetch async below
      |> assign(:resource_keys, @resource_keys) # Assign for template iteration
      |> assign(:show_debug, false) # NEW: Debug panel visibility
      |> assign(:debug_enabled, @debug_enabled) # NEW: Pass flag to template
      |> recalculate_occupation_limits() # Calculate initial limits

    # Fetch leaderboard async after mount
    send(self(), :fetch_leaderboard)

    if connected?(socket) do
      :timer.send_interval(trunc(1000 * @tick_interval), self(), :tick)
      WindyfallWeb.Endpoint.subscribe("leaderboard")
    end
    {:ok, socket}
  end

  defp default_game_state() do
     %{
        "score" => 0.0,
        "player_name" => "Guest #{Windyfall.Accounts.Guest.new_id()}",
        "resources" => Map.new(@resource_keys, fn r -> {Atom.to_string(r), 0.0} end),
        "buildings" => Map.new(Map.keys(@buildings), fn b -> {"building_#{b}", 0} end),
        "occupations" => Map.new(Map.keys(@occupations), fn o -> {"occupation_#{o}", 0} end),
        "researches_done" => [],
        "boosts" => 5,
        "boosting" => false,
        "boost_timer" => 0.0,
        "boost_recovery_time" => @boost_recovery * 1.0,
        "building_progress" => %{}
      }
  end

  def render(assigns) do
    ~H"""
    <div class="p-4 sm:p-6 lg:p-8">
      <%= if @debug_enabled do %>
        <details class="mb-6 p-4 border-2 border-dashed border-red-400 bg-red-50 rounded-lg" open={@show_debug}>
           <summary
             class="cursor-pointer font-bold text-red-700 hover:text-red-900"
             phx-click="toggle_debug"
             phx-window-keydown="toggle_debug_key"
             phx-key="d"
           >
             Debug Panel (DEV ONLY - Press 'D' to toggle)
           </summary>

           <div class="mt-4 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 text-sm">
             <%# -- Add Resources -- %>
             <form phx-submit="dbg_add_resource" class="space-y-2 p-3 border border-red-200 rounded">
               <h4 class="font-semibold text-red-600">Add Resources</h4>
               <div class="flex gap-2">
                  <select
                    name="resource"
                    required
                    class="flex-1 rounded border-red-300 text-xs p-1 focus:ring-red-500 focus:border-red-500"
                    phx-update="ignore"
                    id="dbg-resource-select"
                  >
                    <%= for key <- @resource_keys do %>
                      <option value={key}><%= Phoenix.Naming.humanize(key) %></option>
                    <% end %>
                  </select>
                  <input type="number" name="amount" value="1000" step="100" required class="w-24 rounded border-red-300 text-xs p-1"/>
               </div>
               <button type="submit" class="w-full bg-red-200 hover:bg-red-300 text-red-800 px-2 py-1 rounded text-xs">Add Amount</button>
             </form>

             <%# -- Complete Research -- %>
             <form phx-submit="dbg_complete_research" class="space-y-2 p-3 border border-red-200 rounded">
                <h4 class="font-semibold text-red-600">Complete Research</h4>
                <select
                  name="research"
                  required
                  class="w-full rounded border-red-300 text-xs p-1 focus:ring-red-500 focus:border-red-500"
                  id="dbg-research-select"
                  phx-update="ignore"
                >
                  <option value="" disabled selected>-- Select Research --</option>
                  <%= for {r_key, r_data} <-@researches(), !MapSet.member?(@researches_done, r_key) do %>
                     <option value={r_key}><%= r_data.name %></option>
                  <% end %>
                </select>
               <button type="submit" class="w-full bg-red-200 hover:bg-red-300 text-red-800 px-2 py-1 rounded text-xs">Complete Selected</button>
             </form>

             <%# -- Add Building -- %>
              <form phx-submit="dbg_add_building" class="space-y-2 p-3 border border-red-200 rounded">
                <h4 class="font-semibold text-red-600">Add Building</h4>
                <div class="flex gap-2">
                   <select
                     name="building"
                     required
                     class="flex-1 rounded border-red-300 text-xs p-1 focus:ring-red-500 focus:border-red-500"
                     id="dbg-building-select"
                     phx-update="ignore"
                   >
                     <option value="" disabled selected>-- Select Building --</option>
                     <%= for {b_key, b_data} <- buildings() do %>
                        <option value={b_key}><%= b_data.name %></option>
                     <% end %>
                   </select>
                   <input type="number" name="amount" value="1" min="1" required class="w-16 rounded border-red-300 text-xs p-1"/>
                </div>
                <button type="submit" class="w-full bg-red-200 hover:bg-red-300 text-red-800 px-2 py-1 rounded text-xs">Add Amount</button>
              </form>

              <%# -- Set Score -- %>
              <form phx-submit="dbg_set_score" class="space-y-2 p-3 border border-red-200 rounded">
                 <h4 class="font-semibold text-red-600">Set Score</h4>
                 <input type="number" name="score" value={trunc(@score)} step="10000" required class="w-full rounded border-red-300 text-xs p-1"/>
                 <button type="submit" class="w-full bg-red-200 hover:bg-red-300 text-red-800 px-2 py-1 rounded text-xs">Set Score</button>
              </form>

              <%# -- Reset State -- %>
              <div class="p-3 border border-red-200 rounded flex items-center">
                <button
                  phx-click="dbg_reset_state"
                  phx-confirm="Reset all game progress for this session?"
                  class="w-full bg-red-500 hover:bg-red-600 text-white px-2 py-1 rounded text-xs"
                 >
                  Reset Game State
                 </button>
              </div>

              <%# -- Save Debug State -- %>
              <div class="p-3 border border-red-200 rounded flex items-center">
                <button
                  phx-click="dbg_save_state"
                  phx-confirm="Save current state? This will overwrite previous saves."
                  class="w-full bg-orange-400 hover:bg-orange-500 text-white px-2 py-1 rounded text-xs"
                 >
                  Save Current State
                 </button>
              </div>

           </div>
         </details>
      <% end %>

      <%!-- Header Row: Player Name, Score, Boost Status --%>
      <div class="flex flex-wrap items-center justify-between gap-4 mb-6 pb-4 border-b border-[var(--color-border)]">
        <h1 class="text-2xl font-bold text-[var(--color-text)]">
          <%= @player_name %>'s Settlement
        </h1>
        <div class="flex items-center gap-4 text-sm">
          <span class="text-[var(--color-text-secondary)]">Score: <span class="font-semibold text-[var(--color-text)]"><%= trunc(@score) %></span></span>

          <div class="flex items-center gap-2">
             <button
               class="water-button px-3 py-1.5 text-xs rounded-full disabled:opacity-50 disabled:cursor-not-allowed"
               phx-click="boost"
               disabled={@boosts == 0 || @boosting}>
               Boost (<%= @boosts %>)
             </button>
             <%= if @boosting do %>
               <span class="text-[var(--color-primary)] animate-pulse text-xs font-medium">(Active: <%= trunc(@boost_timer) %>s)</span>
             <% else %>
               <%= if @boosts < 5 do %>
                  <span class="text-[var(--color-text-tertiary)] text-xs">(Recover: <%= trunc(@boost_recovery_time) %>s)</span>
               <% end %>
             <% end %>
           </div>
        </div>
      </div>

      <div class="flex flex-col lg:flex-row gap-6 lg:gap-8">
        <%!-- Left Sidebar - Resources --%>
        <aside class="lg:sticky lg:top-6 lg:h-[calc(100vh-3rem)] lg:w-72 lg:overflow-y-auto lg:pr-4 scrollbar-thin scrollbar-thumb-gray-300 hover:scrollbar-thumb-gray-400">
          <div class="bg-[var(--color-surface)] p-4 rounded-lg shadow-sm border border-[var(--color-border)]">
            <h2 class="text-lg font-semibold text-[var(--color-text)] mb-4">Resources</h2>
            <div class="space-y-1.5">
              <%= for resource <- @resource_keys, value = @resources[resource], delta = @deltas[resource], value > 0 or delta != 0 do %>
                <div class="flex items-center justify-between p-2 bg-[var(--color-surface-alt)]/50 rounded">
                  <div class="flex items-center gap-1.5 min-w-0 flex-1">
                    <span class="font-medium text-sm text-[var(--color-text-secondary)] truncate">
                      <%= Phoenix.Naming.humanize(resource) %>
                    </span>
                    <%= if delta != 0 do %>
                      <span class={
                        "text-xs font-mono #{if delta >= 0, do: "text-green-600", else: "text-red-600"}"
                      }>
                        (<%= if delta >= 0 do %>+<% else %>−<% end %><%= :erlang.float_to_binary(abs(delta), decimals: 1) %>/s)
                      </span>
                    <% end %>
                  </div>
                  <span class="font-mono text-sm text-[var(--color-text)] whitespace-nowrap ml-2">
                    <%= format_resource_value(value) %>
                  </span>
                </div>
              <% end %>
            </div>
          </div>

          <%!-- Leaderboard (Moved to sidebar) --%>
          <div class="mt-6 bg-[var(--color-surface)] p-4 rounded-lg shadow-sm border border-[var(--color-border)]">
             <h2 class="text-lg font-semibold text-[var(--color-text)] mb-4">Leaderboard</h2>
             <%= if @all_sessions == [] do %>
              <p class="text-sm text-[var(--color-text-secondary)]">Loading scores...</p>
             <% else %>
              <ul class="space-y-1.5 text-sm">
                <%= for session <- @all_sessions do %>
                  <li class="flex justify-between items-center p-1.5 rounded bg-[var(--color-surface-alt)]/50">
                    <span class="text-[var(--color-text-secondary)] truncate"><%= session["player_name"] %></span>
                    <span class="font-medium text-[var(--color-text)]"><%= Decimal.div_int(session["score"], Decimal.new(1)) %></span>
                  </li>
                <% end %>
              </ul>
             <% end %>
          </div>
        </aside>

        <%!-- Main Content Area --%>
        <main class="flex-1 space-y-6">
          <%!-- Quick Actions --%>
          <section class="bg-[var(--color-surface)] p-4 rounded-lg shadow-sm border border-[var(--color-border)]">
            <h2 class="text-lg font-semibold text-[var(--color-text)] mb-3">Gather Resources</h2>
            <div class="grid grid-cols-3 gap-3">
              <%= for {action, resource, icon} <- [{:food, "Food", "hero-beaker"}, {:wood, "Wood", "hero-rectangle-stack"}, {:stone, "Stone", "hero-cube-transparent"}] do %>
                <button
                  class="flex flex-col items-center justify-center gap-1 p-3 bg-[var(--color-primary)]/10 hover:bg-[var(--color-primary)]/20 text-[var(--color-primary-dark)] rounded-lg transition-colors text-sm font-medium focus:outline-none focus:ring-2 focus:ring-[var(--color-primary)] focus:ring-offset-1"
                  phx-click="instant-action"
                  phx-value-action={action}
                >
                  <.icon name={icon} class="w-5 h-5 mb-0.5"/>
                  +1 <%= resource %>
                </button>
              <% end %>
            </div>
          </section>

          <%!-- Research Projects --%>
          <section class="bg-[var(--color-surface)] p-4 rounded-lg shadow-sm border border-[var(--color-border)]">
            <h2 class="text-lg font-semibold text-[var(--color-text)] mb-3">Research</h2>
            <div class="grid grid-cols-1 md:grid-cols-2 gap-3">
              <%= for {research_name, research} <- researches(),
                      show_research = !MapSet.member?(@researches_done, research_name) && has_requirements?(research_name, @researches_done) && has_building_requirements?(research, @buildings) do %>
                <%= if show_research do %>
                  <div class="p-3 bg-[var(--color-surface-alt)]/50 rounded-md border border-[var(--color-border)] hover:border-[var(--color-primary)]/30 transition-colors flex flex-col justify-between">
                     <div>
                       <h3 class="font-medium text-[var(--color-text)]"><%= research[:name] %></h3>
                       <div class="text-xs text-[var(--color-text-secondary)] mt-1 space-x-2">
                         <%= if cost = Map.get(research, :cost) do %>
                           <span>Costs:</span>
                           <%= for {res, cost_val} <- cost do %>
                             <span class="whitespace-nowrap"><%= Phoenix.Naming.humanize(res) %>: <span class={if @resources[res] >= cost_val, do: "text-green-600", else: "text-red-500"}><%= cost_val %></span></span>
                           <% end %>
                         <% else %>
                          <span class="text-[var(--color-text-tertiary)]">No resource cost</span>
                         <% end %>
                       </div>
                       <div class="mt-1 text-xs text-[var(--color-text-tertiary)]">
                          <%= humanize_requirements(research) %>
                       </div>
                     </div>
                      <button
                        class="mt-2 w-full px-3 py-1.5 bg-[var(--color-primary)]/80 hover:bg-[var(--color-primary)] text-white rounded text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
                        phx-click="research"
                        phx-value-name={research_name}
                        disabled={!can_research?(research_name, @researches_done, @resources, @buildings)}
                        phx-disable-with="Researching..."
                      >
                        Research
                      </button>
                  </div>
                <% end %>
              <% end %>
              <%= if Enum.empty?(researches() |> Enum.filter(fn {rn, r} -> !MapSet.member?(@researches_done, rn) && has_requirements?(rn, @researches_done) && has_building_requirements?(r, @buildings) end)) do %>
                <p class="text-sm text-[var(--color-text-secondary)] md:col-span-2">No available research projects.</p>
              <% end %>
            </div>
          </section>

          <%!-- Buildings --%>
          <section class="bg-[var(--color-surface)] p-4 rounded-lg shadow-sm border border-[var(--color-border)]">
            <h2 class="text-lg font-semibold text-[var(--color-text)] mb-3">Build</h2>
             <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
              <%= for {building_name, building} <- buildings(), show_building = MapSet.subset?(building[:require], @researches_done) do %>
                <%= if show_building do %>
                  <.live_component module={BuildItemComponent} id={"build-item-#{building_name}"}>
                    <:tooltip>
                      <div class="p-2 bg-[var(--color-surface)] rounded-md shadow-lg border border-[var(--color-border)] min-w-[220px] text-xs">
                        <h4 class="font-medium mb-1 text-sm text-[var(--color-text)]"><%= building[:name] %></h4>
                        <%= if building[:max] do %>
                          <div class="text-[var(--color-text-secondary)] mb-1">Max: <%= building[:max] %></div>
                        <% end %>
                        <%= if !at_max?(building_name, @buildings) do %>
                          <div class="text-[var(--color-text-secondary)] border-t border-[var(--color-border)] pt-1 mt-1">
                            <span class="font-medium text-[var(--color-text)]">Next Cost:</span>
                            <%= for {res, cost} <- @next_costs[building_name] do %>
                              <div class="flex justify-between">
                                <span><%= Phoenix.Naming.humanize(res) %>:</span>
                                <span class={if @resources[res] >= cost, do: "text-green-600", else: "text-red-500"}>
                                  <%= format_resource_value(cost) %>
                                </span>
                              </div>
                            <% end %>
                          </div>
                        <% else %>
                           <div class="text-green-600 text-center mt-1 border-t border-[var(--color-border)] pt-1">Maximum reached</div>
                        <% end %>
                        <%!-- TODO: Add effects description here --%>
                      </div>
                    </:tooltip>

                    <button
                      class={[
                        "p-3 rounded-md border transition-all text-left w-full relative",
                        (if can_build?(building_name, @resources, @next_costs, @buildings),
                          do: "bg-[var(--color-surface-alt)]/50 hover:border-[var(--color-primary)]/50 border-[var(--color-border)]",
                          else: "bg-gray-100 border-gray-200 text-gray-400 cursor-not-allowed")
                      ]}
                      phx-click="build-building"
                      phx-value-building-name={building_name}
                      disabled={!can_build?(building_name, @resources, @next_costs, @buildings)}
                      phx-disable-with="..."
                      aria-label={"Build #{building[:name]}"}
                    >
                       <div class="flex justify-between items-start">
                         <div class="min-w-0">
                           <h3
                             class={[
                               "font-medium text-sm truncate",
                               # Wrap the 'if' expression in parentheses
                               (if can_build?(building_name, @resources, @next_costs, @buildings),
                                 do: "text-[var(--color-text)]",
                                 else: "text-gray-500")
                             ]}
                           >
                              <%= building[:name] %>
                           </h3>
                           <div class={["text-xs mt-0.5", (if can_build?(building_name, @resources, @next_costs, @buildings), do: "text-[var(--color-text-secondary)]", else: "text-gray-400")]}>
                             Owned: <span class="font-medium"><%= @buildings[building_name] %></span>
                             <%= if building[:max] do %>/ <%= building[:max] %><% end %>
                           </div>
                         </div>
                         <%= if at_max?(building_name, @buildings) do %>
                            <span class="text-xs bg-green-100 text-green-700 px-1.5 py-0.5 rounded-full font-medium">MAX</span>
                         <% else %>
                            <.icon name="hero-plus-circle" class="w-5 h-5 text-[var(--color-primary)]/70"/>
                         <% end %>
                       </div>
                       <%= if building[:parts] && @building_progress[building_name] do %>
                         <div class="mt-1 w-full bg-gray-200 rounded-full h-1.5 dark:bg-gray-700">
                           <div class="bg-[var(--color-accent)] h-1.5 rounded-full" style={"width: #{(@building_progress[building_name].parts || 0) / building[:parts] * 100}%"}></div>
                         </div>
                         <div class="text-xs text-[var(--color-text-tertiary)] text-right mt-0.5">
                            <%= @building_progress[building_name].parts || 0 %> / <%= building[:parts] %>
                         </div>
                       <% end %>
                    </button>
                  </.live_component>
                <% end %>
              <% end %>
            </div>
          </section>

          <%!-- Occupations --%>
          <section class="bg-[var(--color-surface)] p-4 rounded-lg shadow-sm border border-[var(--color-border)]">
             <div class="flex justify-between items-center mb-3">
                <h2 class="text-lg font-semibold text-[var(--color-text)]">Assign Workers</h2>
                <span class="text-sm font-medium text-[var(--color-text-secondary)]">
                   Idle Workers: <span class="text-[var(--color-primary)] font-bold text-base"><%= @idle_workers %></span>
                </span>
             </div>
             <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
              <%= for {occupation, details} <- occupations(), show_occ = MapSet.subset?(details[:require], @researches_done) do %>
                <%= if show_occ do %>
                  <div class="bg-[var(--color-surface-alt)]/50 rounded-md border border-[var(--color-border)] p-3">
                     <div class="flex items-center justify-between mb-1.5">
                       <h3 class="font-medium text-sm text-[var(--color-text)]">
                         <%= Phoenix.Naming.humanize(occupation) %>
                       </h3>
                       <span class="text-xs text-[var(--color-text-secondary)] bg-gray-200/50 px-1.5 py-0.5 rounded-full">
                          <%= @occupations[occupation] %> / <%= @max_occupations[occupation] %> Max
                       </span>
                     </div>
                     <div class="flex items-center justify-between gap-2">
                       <button
                         class={[
                           "p-1.5 rounded-full transition-colors",
                           # Wrap the 'if' in parentheses
                           (if @occupations[occupation] > 0,
                             do: "bg-red-100 hover:bg-red-200 text-red-700",
                             else: "bg-gray-200 text-gray-400 cursor-not-allowed")
                         ]}
                         phx-click="unassign-worker"
                         phx-value-occupation={Atom.to_string(occupation)}
                         disabled={@occupations[occupation] == 0}
                         aria-label={"Unassign #{occupation}"}
                       >
                          <.icon name="hero-minus" class="w-4 h-4"/>
                       </button>
                       <span class="text-lg font-medium text-[var(--color-text)] tabular-nums">
                          <%= @occupations[occupation] %>
                       </span>
                       <button
                         class={[
                           "p-1.5 rounded-full transition-colors",
                           # Wrap the 'if' in parentheses
                           (if can_assign_more?(@idle_workers, @occupations[occupation], @max_occupations[occupation]),
                             do: "bg-green-100 hover:bg-green-200 text-green-700",
                             else: "bg-gray-200 text-gray-400 cursor-not-allowed")
                         ]}
                         phx-click="assign-worker"
                         phx-value-occupation={Atom.to_string(occupation)}
                         disabled={!can_assign_more?(@idle_workers, @occupations[occupation], @max_occupations[occupation])}
                         aria-label={"Assign #{occupation}"}
                       >
                          <.icon name="hero-plus" class="w-4 h-4"/>
                       </button>
                     </div>
                   </div>
                <% end %>
              <% end %>
             </div>
          </section>

        </main>
      </div>
    </div>
    """
  end

  # --- Event Handlers (Largely Unchanged Logic, Minor Updates) ---

  def handle_info(:fetch_leaderboard, socket) do
    {:noreply, assign(socket, :all_sessions, GameSessions.all_sessions())}
  end

  def handle_event("toggle_debug", _, socket) do
    if @debug_enabled do
      {:noreply, assign(socket, :show_debug, !socket.assigns.show_debug)}
    else
      {:noreply, socket} # Ignore if debug not enabled
    end
  end

  def handle_event("toggle_debug_key", %{"key" => "d"}, socket) do
    if @debug_enabled do
      {:noreply, assign(socket, :show_debug, !socket.assigns.show_debug)}
    else
      {:noreply, socket} # Ignore if debug not enabled
    end
  end
  def handle_event("toggle_debug_key", _, socket), do: {:noreply, socket} # Ignore other keys


  def handle_event("dbg_add_resource", %{"resource" => res_str, "amount" => amt_str}, socket) do
    if @debug_enabled do
      resource = String.to_existing_atom(res_str)
      case Float.parse(amt_str) do
        {amount, ""} when amount > 0 ->
          new_socket = update(socket, :resources, &Map.update!(&1, resource, fn current -> current + amount end))
          {:noreply, new_socket}
        _ ->
         {:noreply, put_flash(socket, :error, "Invalid amount for resource.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("dbg_complete_research", %{"research" => res_str}, socket) do
     if @debug_enabled do
       research = String.to_existing_atom(res_str)
       if Map.has_key?(@researches, research) do
         new_socket = update(socket, :researches_done, &MapSet.put(&1, research))
         # Note: Effects of research (like new buildings/occupations being available)
         # will automatically show up on the next render. Delta recalculation happens on tick.
         {:noreply, new_socket}
       else
          {:noreply, put_flash(socket, :error, "Invalid research selected.")}
       end
     else
       {:noreply, socket}
     end
  end

   def handle_event("dbg_add_building", %{"building" => bldg_str, "amount" => amt_str}, socket) do
     if @debug_enabled do
       building = String.to_existing_atom(bldg_str)
       case Integer.parse(amt_str) do
         {amount, ""} when amount > 0 ->
           if Map.has_key?(@buildings, building) do
             current_amount = socket.assigns.buildings[building]
             new_amount = current_amount + amount

             # Check max limit if exists
             max = Map.get(@buildings[building], :max, :infinity)
             final_amount = if max == :infinity, do: new_amount, else: min(new_amount, max)

             # Directly update building count
             socket = update(socket, :buildings, &Map.put(&1, building, final_amount))

             # Update next cost for this specific building
             new_cost = building_cost(building, final_amount)
             socket = update(socket, :next_costs, &Map.put(&1, building, new_cost))

             # Recalculate occupation limits as buildings affect them
             socket = recalculate_occupation_limits(socket)

             {:noreply, socket}
           else
             # Handle invalid building name here
             {:noreply, put_flash(socket, :error, "Invalid building selected.")}
           end

         _ ->
           {:noreply, put_flash(socket, :error, "Invalid building or amount.")}
       end
     else
       {:noreply, socket}
     end
   end

   def handle_event("dbg_set_score", %{"score" => score_str}, socket) do
     if @debug_enabled do
        case Float.parse(score_str) do
          {score, ""} ->
            {:noreply, assign(socket, :score, score)}
          _ ->
            {:noreply, put_flash(socket, :error, "Invalid score.")}
        end
     else
        {:noreply, socket}
     end
   end

   def handle_event("dbg_reset_state", _, socket) do
     if @debug_enabled do
       # Re-initialize state using the default helper
       game_state = default_game_state()

       # Re-assign all relevant state variables similar to mount
       initial_score = Map.get(game_state, "score", 0.0)
       initial_resources = Map.new(@resource_keys, fn resource ->
         {resource, Map.get(game_state, Atom.to_string(resource), 0.0)}
       end)
       initial_buildings = Map.new(Map.keys(@buildings), fn building_name ->
         {building_name, Map.get(game_state, "building_#{building_name}", 0)}
       end)
       initial_occupations = Map.new(Map.keys(@occupations), fn occupation ->
         {occupation, Map.get(game_state, "occupation_#{occupation}", 0)}
       end)
       researches_done = MapSet.new(Map.get(game_state, "researches_done", []) |> Enum.map(&String.to_existing_atom/1))
       next_costs = Map.new(Map.keys(@buildings), fn building_name ->
         {building_name, building_cost(building_name, initial_buildings[building_name])}
       end)
       initial_deltas = Map.new(@resource_keys, fn k -> {k, 0.0} end)


       new_socket =
         socket
         |> assign(:score, initial_score)
         |> assign(:resources, initial_resources)
         |> assign(:buildings, initial_buildings)
         |> assign(:occupations, initial_occupations)
         |> assign(:building_progress, Map.get(game_state, "building_progress", %{}))
         |> assign(:researches_done, researches_done)
         |> assign(:next_costs, next_costs)
         |> assign(:deltas, initial_deltas) # Reset deltas display
         |> assign(:boosts, Map.get(game_state, "boosts", 5))
         |> assign(:boosting, Map.get(game_state, "boosting", false))
         |> assign(:boost_timer, Map.get(game_state, "boost_timer", 0.0))
         |> assign(:boost_recovery_time, Map.get(game_state, "boost_recovery_time", @boost_recovery * 1.0))
         |> recalculate_occupation_limits() # Recalculate limits after reset

        # Optionally clear the persisted state (use with caution)
        # GameSessions.update_session(socket.assigns.game_session, default_game_state())

       {:noreply, put_flash(new_socket, :info, "Game state reset (session not cleared).")}
     else
       {:noreply, socket}
     end
   end

  def handle_event("dbg_save_state", _, socket) do
    if @debug_enabled do
      # Persist current state forcefully
      persist_game_state(
        socket.assigns.game_session,
        socket,
        socket.assigns.score,
        socket.assigns.resources,
        socket.assigns.boosts,
        socket.assigns.boosting,
        socket.assigns.boost_timer,
        socket.assigns.boost_recovery_time
      )
       {:noreply, put_flash(socket, :info, "Current game state saved.")}
    else
       {:noreply, socket}
    end
  end

  def handle_event("boost", _, socket) do
    # Logic is fine, just ensure assigns are updated
    consume_boost = socket.assigns.boosts > 0 && !socket.assigns.boosting
    {boosts, boosting, boost_timer} = if consume_boost do
      {socket.assigns.boosts - 1, true, @boost_length}
    else
      {socket.assigns.boosts, socket.assigns.boosting, socket.assigns.boost_timer}
    end
    socket =
      socket
      |> assign(:boosts, boosts)
      |> assign(:boosting, boosting)
      |> assign(:boost_timer, boost_timer)
    {:noreply, socket}
  end

  def handle_event("instant-action", %{"action" => action}, socket) do
    action_atom = String.to_existing_atom(action)
    {:noreply, update_resource(socket, action_atom, &(&1 + 1.0))} # Ensure float addition
  end

  def handle_event("research", %{"name" => name}, socket) do
    name = String.to_existing_atom(name)
    researches_done = socket.assigns.researches_done
    resources = socket.assigns.resources

    with true <- can_research_reqs?(name, researches_done),
         true <- has_building_requirements?(@researches[name], socket.assigns.buildings),
         :sufficient <- check_resources(resources, Map.get(@researches[name], :cost, %{})) do
      cost = Map.get(@researches[name], :cost, %{})
      socket =
        socket
        |> deduct_resources(cost)
        |> update_research_status(name)
      {:noreply, socket}
    else
      _ -> {:noreply, socket} # Failed check
    end
  end

  def handle_event("build-building", %{"building-name" => building_name}, socket) do
    building_name = String.to_existing_atom(building_name)
    building_num = socket.assigns[:buildings][building_name]

    if at_max?(building_name, socket.assigns.buildings) do
      {:noreply, socket}
    else
      build_building(socket, building_name, building_num)
    end
  end

  def handle_event("assign-worker", %{"occupation" => occupation}, socket) do
    occupation = String.to_existing_atom(occupation)
    socket = if can_assign_more?(socket.assigns.idle_workers, socket.assigns.occupations[occupation], socket.assigns.max_occupations[occupation]) do
      socket
      |> update(:occupations, &Map.update!(&1, occupation, fn val -> val + 1 end))
      |> recalculate_occupation_limits()
    else
      socket
    end
    {:noreply, socket}
  end

  def handle_event("unassign-worker", %{"occupation" => occupation}, socket) do
    occupation = String.to_existing_atom(occupation)
    socket = if socket.assigns.occupations[occupation] > 0 do
      socket
      |> update(:occupations, &Map.update!(&1, occupation, fn val -> val - 1 end))
      |> recalculate_occupation_limits()
    else
     socket
    end
    {:noreply, socket}
  end

  def handle_info(:tick, socket) do
    # 1. Update score
    new_score = socket.assigns.score + 1 # Simple increment for now

    # 2. Update Boost Timers
    {boost_timer, boosting} = update_boost_timer(socket.assigns.boost_timer, socket.assigns.boosting)
    {boosts, boost_recovery_time} = update_boost_recovery(socket.assigns.boosts, socket.assigns.boost_recovery_time)

    # 3. Calculate Multipliers (including boost)
    boost_factor = if boosting, do: @boost_multiplier, else: 1.0
    multipliers = compute_boosts(socket.assigns.buildings, socket.assigns.researches_done)

    # 4. Calculate Deltas
    deltas = calculate_deltas(socket.assigns, multipliers, boost_factor)

    # 5. Apply Deltas to Resources
    new_resources = apply_deltas(socket.assigns.resources, deltas)

    # 6. Persist Game State
    persist_game_state(socket.assigns.game_session, socket, new_score, new_resources, boosts, boosting, boost_timer, boost_recovery_time)
    WindyfallWeb.Endpoint.broadcast("leaderboard", "update_score", nil) # Notify others about potential score changes

    # 7. Update Socket State
    socket = socket
      |> assign(:resources, new_resources)
      |> assign(:deltas, per_second_deltas(deltas)) # Convert tick deltas to per-second for display
      |> assign(:score, new_score)
      |> assign(:boost_timer, boost_timer)
      |> assign(:boosting, boosting)
      |> assign(:boosts, boosts)
      |> assign(:boost_recovery_time, boost_recovery_time)
      |> recalculate_occupation_limits() # Recalculate idle workers in case population changed

    {:noreply, socket}
  end

  # --- Helper Functions (Modified and New) ---

  defp calculate_deltas(assigns, multipliers, boost_factor) do
    # Initialize deltas
    deltas = Map.new(@resource_keys, fn k -> {k, 0.0} end)

    # Housing consumption check
    housing_consumption = calculate_housing_consumption(assigns.buildings)
    potential_food_production = calculate_potential_food(assigns, multipliers, boost_factor)
    current_food = assigns.resources.food
    housing_enabled = (current_food + potential_food_production) >= housing_consumption

    deltas = if housing_enabled do
      deltas
      |> Map.update!(:food, &(&1 - housing_consumption)) # Apply consumption first
      |> add_housing_generation(assigns.buildings, multipliers, boost_factor)
      |> process_occupations_deltas(assigns.occupations, assigns.resources, multipliers, boost_factor)
    else
      # If housing is disabled, maybe only apply negative food delta if still possible?
      # Or simply generate nothing from housing/occupations consuming food.
      # Let's keep it simple: no generation if housing fails.
      deltas
    end

    # Add generation from non-consuming buildings (always active)
    process_non_housing_buildings_deltas(deltas, assigns.buildings, multipliers, boost_factor)
  end

  defp apply_deltas(resources, deltas) do
     Map.new(resources, fn {resource, value} ->
      new_value = value + Map.get(deltas, resource, 0.0)
      {resource, max(new_value, 0.0)} # Ensure resources don't go below zero
    end)
  end

  defp update_boost_timer(timer, boosting) do
    if boosting and timer > 0 do
      new_timer = timer - @tick_interval
      if new_timer <= 0, do: {0.0, false}, else: {new_timer, true}
    else
      {0.0, false}
    end
  end

  defp update_boost_recovery(boosts, recovery_timer) do
    if boosts < 5 and recovery_timer > 0 do
      new_timer = recovery_timer - @tick_interval
      if new_timer <= 0 do
        {boosts + 1, @boost_recovery}
      else
        {boosts, new_timer}
      end
    else
      {boosts, recovery_timer}
    end
  end

  defp add_housing_generation(deltas, buildings, multipliers, boost_factor) do
     Enum.reduce(buildings, deltas, fn {building_name, count}, acc ->
      building = @buildings[building_name]
      # Only process buildings that *consume* resources (implying they are housing-dependent)
      if Map.has_key?(building, :consume) do
        generation = Map.get(building, :generation, %{})
        Enum.reduce(generation, acc, fn {resource, rate}, deltas_acc ->
          all_boost = Map.get(multipliers, {:all, resource}, 1.0)
          # Apply boost factor to generation
          delta = rate * count * @tick_interval * all_boost * boost_factor
          Map.update(deltas_acc, resource, delta, &(&1 + delta))
        end)
      else
        acc # Skip non-consuming buildings here
      end
    end)
  end

  defp process_occupations_deltas(deltas, occupations, current_resources, multipliers, boost_factor) do
    Enum.reduce(occupations, deltas, fn {occupation, number}, deltas_acc ->
      if number == 0 do
        deltas_acc
      else
        process_occupation_deltas(deltas_acc, occupation, number, current_resources, multipliers, boost_factor)
      end
    end)
  end

  # Modified to check available resources *before* applying consumption
  defp process_occupation_deltas(deltas, occupation, number, current_resources, multipliers, boost_factor) do
     details = @occupations[occupation]
     consumption = Map.get(details, :consume, %{})
     required = Enum.into(consumption, %{}, fn {res, rate} -> {res, rate * number * @tick_interval} end)

     # Check if enough resources exist *currently* (before this tick's generation)
     # We also consider the *deltas accumulated so far this tick* for other processes
     can_consume = Enum.all?(required, fn {res, amt} ->
       (Map.get(current_resources, res, 0.0) + Map.get(deltas, res, 0.0)) >= amt
     end)

     if can_consume do
       # Apply consumption to deltas
       deltas_after_consume = Enum.reduce(required, deltas, fn {res, amt}, acc ->
         Map.update!(acc, res, &(&1 - amt))
       end)
       # Apply generation to deltas
       Enum.reduce(details.generation, deltas_after_consume, fn {res, rate}, acc ->
         occupation_boost = Map.get(multipliers, {occupation, res}, 1.0)
         all_boost = Map.get(multipliers, {:all, res}, 1.0)
         total_boost = occupation_boost * all_boost
         # Apply boost factor to generation
         delta = rate * number * @tick_interval * total_boost * boost_factor
         Map.update(acc, res, delta, &(&1 + delta))
       end)
     else
       deltas # Cannot consume, so no generation either
     end
  end

  defp process_non_housing_buildings_deltas(deltas, buildings, multipliers, boost_factor) do
    Enum.reduce(buildings, deltas, fn {building_name, count}, acc ->
      building = @buildings[building_name]
      # Only process buildings that *don't* consume (implying not housing-dependent)
      if !Map.has_key?(building, :consume) do
        generation = Map.get(building, :generation, %{})
        Enum.reduce(generation, acc, fn {res, rate}, deltas_acc ->
          all_boost = Map.get(multipliers, {:all, res}, 1.0)
          # Apply boost factor to generation
          delta = rate * count * @tick_interval * all_boost * boost_factor
          Map.update(deltas_acc, res, delta, &(&1 + delta))
        end)
      else
        acc # Skip consuming buildings here
      end
    end)
  end

  defp persist_game_state(game_session, socket, score, resources, boosts, boosting, boost_timer, boost_recovery_time) do
    # Prepare state map for persistence
    state_to_save = %{
      "score" => score,
      "player_name" => socket.assigns.player_name,
      "boosts" => boosts,
      "boosting" => boosting,
      "boost_timer" => boost_timer,
      "boost_recovery_time" => boost_recovery_time,
      "researches_done" => socket.assigns.researches_done |> Enum.map(&Atom.to_string/1)
    }
    |> Map.merge(Map.new(resources, fn {k, v} -> {Atom.to_string(k), v} end))
    |> Map.merge(Map.new(socket.assigns.buildings, fn {k, v} -> {"building_#{k}", v} end))
    |> Map.merge(Map.new(socket.assigns.occupations, fn {k, v} -> {"occupation_#{k}", v} end))
    |> Map.merge(Map.new(socket.assigns.building_progress, fn {k, v} -> {"progress_#{k}", v} end))

    GameSessions.update_session(game_session, state_to_save)
  end

  defp per_second_deltas(deltas) do
    Map.new(deltas, fn {resource, delta} ->
      {resource, delta / @tick_interval}
    end)
  end

  # --- UI Helper Functions ---
  defp format_resource_value(value) when is_float(value) do
    # Simple formatting, could be expanded (e.g., K, M suffixes)
    :erlang.float_to_binary(value, decimals: 1)
  end
  defp format_resource_value(value), do: value # Handle integers or other types

  # Renamed from can_research? to avoid conflict, checks only requirements
  defp can_research_reqs?(name, completed) do
     !MapSet.member?(completed, name) && has_requirements?(name, completed)
  end

  # Updated can_research? to include resource check
  defp can_research?(name, completed, resources, owned_buildings) do
    research = @researches[name]
    cost = Map.get(research, :cost, %{})
    can_research_reqs?(name, completed) &&
    has_building_requirements?(research, owned_buildings) && # Check building reqs too
    check_resources(resources, cost) == :sufficient
  end

  # Updated can_build? to use next_costs from assigns
  defp can_build?(building_name, resources, next_costs, owned_buildings) do
    building_data = @buildings[building_name]
    max = Map.get(building_data, :max, :infinity)
    current_owned_count = Map.get(owned_buildings, building_name, 0)

    not_at_max = (max == :infinity or current_owned_count < max)

    sufficient_resources = Enum.all?(Map.get(building_data, :cost, %{}), fn {res, _} ->
      cost = Map.get(next_costs[building_name], res, 0.0) # Get precalculated cost
      resources[res] >= cost
    end)

    not_at_max and sufficient_resources
  end

  # Other helper functions like has_requirements?, has_building_requirements?, at_max?,
  # check_resources, deduct_resources, update_research_status, building_cost,
  # try_build, add_building, max_occupation, recalculate_occupation_limits,
  # humanize_requirements remain largely the same logic but use assigns.
  # Make sure they access socket.assigns correctly. Example:
  defp check_resources(resources, cost) do
    if Enum.all?(cost, fn {resource, amount} -> Map.get(resources, resource, 0.0) >= amount end) do
      :sufficient
    else
      :insufficient
    end
  end

  defp deduct_resources(socket, cost) do
    new_resources = Enum.reduce(cost, socket.assigns[:resources], fn {resource, amount}, resources_acc ->
      Map.update!(resources_acc, resource, &(&1 - amount))
    end)
    assign(socket, :resources, new_resources)
  end

  defp update_research_status(socket, name) do
    update(socket, :researches_done, &(MapSet.put(&1, name)))
  end

  defp has_requirements?(name, completed) do
    research = @researches[name]
    required = Map.get(research, :require, []) |> MapSet.new()
    MapSet.subset?(required, completed)
  end

  defp has_building_requirements?(research_details, owned_buildings) do
    requirements = Map.get(research_details, :building_require, %{})
    Enum.all?(requirements, fn {building, number} ->
      Map.get(owned_buildings, building, 0) >= number 
    end)
  end

  defp at_max?(building_name, owned_buildings) do
    building = @buildings[building_name]
    max = Map.get(building, :max, :infinity)
    max != :infinity and Map.get(owned_buildings, building_name, 0) >= max
  end

  defp build_building(socket, building_name, building_num) do
    next_cost = socket.assigns.next_costs[building_name]
    case check_resources(socket.assigns.resources, next_cost) do
      :sufficient ->
        socket = deduct_resources(socket, next_cost)
        num_parts = Map.get(@buildings[building_name], :parts)
        if num_parts do
          progress = Map.get(socket.assigns[:building_progress], building_name, %{})
          new_parts = Map.get(progress, :parts, 0) + 1
          new_progress = Map.put(progress, :parts, new_parts)

          socket = update(socket, :building_progress, &(Map.put(&1, building_name, new_progress)))

          if new_parts >= num_parts do
            add_building(socket, building_name) # Progress complete, add the building level
          else
            socket # Just update progress
          end
        else
          add_building(socket, building_name) # No parts, add building level directly
        end
      :insufficient ->
        socket # Cannot build
    end
    |> then(&{:noreply, &1}) # Wrap the final socket state in {:noreply, socket}
  end

  defp add_building(socket, building_name) do
    next_num = socket.assigns[:buildings][building_name] + 1
    new_costs = building_cost(building_name, next_num)
    socket
    |> update(:buildings, &(Map.put(&1, building_name, next_num)))
    |> update(:next_costs, &(Map.put(&1, building_name, new_costs)))
    |> assign(:building_progress, Map.delete(socket.assigns.building_progress, building_name)) # Reset progress
    |> recalculate_occupation_limits()
  end

  defp max_occupation(occupation, owned_buildings) do
    Enum.reduce(owned_buildings, 0, fn {building_name, count}, acc ->
      # Check if building_name exists in @buildings before accessing
      if building_data = Map.get(@buildings, building_name) do
         contribution = Map.get(building_data, occupation, 0) * count
         acc + contribution
      else
        # Building from assigns not found in static data? Should not happen ideally.
        acc
      end
    end)
  end

  defp recalculate_occupation_limits(socket) do
    owned_buildings = socket.assigns.buildings
    occupations = socket.assigns.occupations

    max_occupations =
      occupations
      |> Map.keys()
      |> Enum.reduce(%{}, fn occupation, acc ->
        max = max_occupation(occupation, owned_buildings)
        Map.put(acc, occupation, max)
      end)

    total_population = Enum.reduce(owned_buildings, 0, fn {building_name, count}, acc ->
      building = @buildings[building_name]
      acc + count * Map.get(building, :population, 0)
    end)

    used_population = Map.values(occupations) |> Enum.sum()
    idle_workers = max(total_population - used_population, 0) # Ensure not negative

    socket
    |> assign(:max_occupations, max_occupations)
    |> assign(:idle_workers, idle_workers)
  end

  defp building_cost(building_name, num_buildings) do
    scaling_amount = @buildings[building_name][:cost_scaling]
    scaling_factor = :math.pow(scaling_amount, num_buildings)
    Map.new(@buildings[building_name][:cost], fn {resource, amount} ->
       {resource, amount * scaling_factor}
     end)
    |> Map.new(fn {res, cost} -> {res, Float.ceil(cost, 1)} end) # Ceil costs to 1 decimal place
  end

  defp can_assign_more?(idle_workers, current, max) do
    idle_workers > 0 && current < max
  end

  defp humanize_requirements(research) do
    # Calculate research text (or nil)
    research_text =
      case Map.get(research, :require, []) do
        [] -> nil # No requirements or empty list
        reqs -> # Non-empty list
          names = Enum.map(reqs, &(@researches[&1][:name]))
          "Research: #{Enum.join(names, ", ")}" # Correct separator
      end

    # Calculate building text (or nil)
    building_text =
      case Map.get(research, :building_require, %{}) do
        %{} = breq_map when map_size(breq_map) > 0 -> # Non-empty map
          building_req_strings = Enum.map(breq_map, fn {b, n} ->
            "#{@buildings[b][:name]} x#{n}"
          end)
          "Buildings: #{Enum.join(building_req_strings, ", ")}" # Correct separator
        _ -> nil # Empty map or key not found
      end

    # Combine the results
    all_reqs = [research_text, building_text] |> Enum.reject(&is_nil/1)

    # Format final output
    case all_reqs do
      [] -> "None"
      list -> Enum.join(list, " • ")
    end
  end

  # Handle leaderboard updates
  def handle_info(%{event: "update_score"}, socket) do
    # Refetch might be heavy, consider only updating if the current player's score changed significantly
    # Or just rely on the periodic fetch via send(self(), :fetch_leaderboard)
    {:noreply, assign(socket, :all_sessions, GameSessions.all_sessions())}
  end

  defp update_resource(socket, resource, value_update) do
    update(socket, :resources, &Map.update!(&1, resource, value_update))
  end

  @doc """
  Calculates the total food consumed per tick by buildings requiring it.
  """
  defp calculate_housing_consumption(buildings) do
    Enum.reduce(buildings, 0.0, fn {building_name, count}, acc ->
      # CORRECTED: Chain Map.get/3
      food_consume_rate =
        Map.get(@buildings, building_name, %{})
        |> Map.get(:consume, %{})
        |> Map.get(:food, 0.0)

      acc + food_consume_rate * count * @tick_interval
    end)
  end

  @doc """
  Calculates the potential food generated per tick from occupations and buildings.
  Used to check if housing consumption can be met *before* applying deltas.
  """
  defp calculate_potential_food(assigns, multipliers, boost_factor) do
    # --- Food from Occupations ---
    food_from_occupations =
      Enum.reduce(assigns.occupations, 0.0, fn {occupation, number}, acc ->
        if number == 0 do
          acc
        else
          details = @occupations[occupation]
          # CORRECTED: Chain Map.get/3
          food_rate =
            Map.get(details, :generation, %{})
            |> Map.get(:food, 0.0)

          occupation_boost = Map.get(multipliers, {occupation, :food}, 1.0)
          all_boost = Map.get(multipliers, {:all, :food}, 1.0)
          total_boost = occupation_boost * all_boost * boost_factor

          acc + food_rate * number * @tick_interval * total_boost
        end
      end)

    # --- Food from Buildings ---
    food_from_buildings =
      Enum.reduce(assigns.buildings, 0.0, fn {building_name, count}, acc ->
        if count == 0 do
          acc
        else
          building = @buildings[building_name]
          # CORRECTED: Chain Map.get/3
          food_rate =
            Map.get(building, :generation, %{})
            |> Map.get(:food, 0.0)

          all_boost = Map.get(multipliers, {:all, :food}, 1.0)
          total_boost = all_boost * boost_factor

          acc + food_rate * count * @tick_interval * total_boost
        end
      end)

    food_from_occupations + food_from_buildings
  end


  @doc """
  Computes a map of multipliers based on active buildings and completed researches.
  """
  defp compute_boosts(buildings, researches_done) do
    # 1. Aggregate boosts from buildings
    building_boost_sources =
      Enum.reduce(buildings, %{}, fn {building_name, count}, acc_sources ->
        if count == 0 do
          acc_sources
        else
          # CORRECTED: Chain Map.get/3
          building_boosts =
            Map.get(@buildings, building_name, %{})
            |> Map.get(:boost, %{})

          Enum.reduce(building_boosts, acc_sources, fn {target, boosts_for_target}, acc_targets ->
            Enum.reduce(boosts_for_target, acc_targets, fn {resource, value}, acc_resources ->
              key = {target, resource}
              contribution = value * count
              Map.update(acc_resources, key, [contribution], &[contribution | &1])
            end)
          end)
        end
      end)

    # 2. Aggregate boosts from researches
    research_boost_sources =
      Enum.reduce(researches_done, %{}, fn research_name, acc_sources ->
        # CORRECTED: Chain Map.get/3
        research_boosts =
          Map.get(@researches, research_name, %{})
          |> Map.get(:boost, %{})

        Enum.reduce(research_boosts, acc_sources, fn {target, boosts_for_target}, acc_targets ->
          Enum.reduce(boosts_for_target, acc_targets, fn {resource, value}, acc_resources ->
            key = {target, resource}
            Map.update(acc_resources, key, [value], &[value | &1])
          end)
        end)
      end)

    # 3. Merge building and research boost lists (logic remains the same)
    all_boost_sources =
      Map.merge(building_boost_sources, research_boost_sources, fn _key, list1, list2 ->
        list1 ++ list2
      end)

    # 4. Calculate final multipliers (logic remains the same)
    Enum.reduce(all_boost_sources, %{}, fn {{target, resource}, list_of_boosts}, acc_multipliers ->
      final_multiplier = Enum.reduce(list_of_boosts, 1.0, fn boost_value, current_multiplier ->
        current_multiplier * (1.0 + boost_value)
      end)
      Map.put(acc_multipliers, {target, resource}, final_multiplier)
    end)
  end

  defp building_effects_description(building_name) do
    building = @buildings[building_name]
    effects = []

    # Population
    effects = if pop = Map.get(building, :population) do
      ["Population: +#{pop}" | effects]
    else
      effects
    end

    # Consumption (per tick, needs conversion)
    effects = if consume = Map.get(building, :consume) do
      consume_desc = Enum.map(consume, fn {res, rate} ->
        per_sec = rate / @tick_interval
        "Consumes #{format_resource_value(per_sec)} #{Phoenix.Naming.humanize(res)}/s"
      end)
      consume_desc ++ effects
    else
      effects
    end

    # Generation (per tick, needs conversion)
    effects = if gen = Map.get(building, :generation) do
      gen_desc = Enum.map(gen, fn {res, rate} ->
        per_sec = rate / @tick_interval
        "Generates #{format_resource_value(per_sec)} #{Phoenix.Naming.humanize(res)}/s"
      end)
      gen_desc ++ effects
    else
      effects
    end

    # Worker Slots
    effects = Enum.reduce(Map.keys(@occupations), effects, fn occ, acc ->
      # Use case with Map.fetch to handle missing key and check value
      case Map.fetch(building, occ) do
        # Pattern match on success AND check if slots > 0 in the guard
        {:ok, slots} when slots > 0 ->
          ["Adds #{slots} #{Phoenix.Naming.humanize(occ)} slot(s)" | acc]
        # Handles both :error (key not found) and {:ok, slots} where slots <= 0
        _ ->
          acc
      end
    end)

    # Boosts
    effects = if boost = Map.get(building, :boost) do
      boost_desc = Enum.flat_map(boost, fn {target, target_boosts} ->
        Enum.map(target_boosts, fn {res, percent} ->
          target_name = if target == :all, do: "All", else: Phoenix.Naming.humanize(target)
          "Boosts #{target_name} #{Phoenix.Naming.humanize(res)} by #{Float.round(percent * 100)}%"
        end)
      end)
      boost_desc ++ effects
    else
      effects
    end


    Enum.reverse(effects) # Reverse to get a more logical order
  end
end
