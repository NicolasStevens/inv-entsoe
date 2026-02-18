#=
dispatch_problem:
- Julia version: 1.5.3
- Author: Nicolas
- Date: 2022-09-05
=#
"""
Function that runs the dicrete investment problem.
"""
function discreteCapacityExpansionModel(data)
    EVA_model = Model(() -> Gurobi.Optimizer(GUROBI_ENV))
    set_optimizer_attribute(EVA_model, "MIPGap", 5e-4) # used to be 1e-4
    
    #### Sets
    nodes = data["nodes"]
    periods = data["periods"]
    generators_exist_keys = data["generators_exist_keys"]
    generators_exist = data["generators_exist"]
    generators_new_keys = data["generators_new_keys"]
    generators_new = data["generators_new"]
    dsr_keys = data["dsr_keys"]
    dsr = data["dsr"]
    line_from_keys = data["line_from_keys"]
    line_from = data["line_from"]
    line_to_keys = data["line_to_keys"]
    line_to = data["line_to"]
    hydro_types = data["hydro_types"]
    ps_hydro = ["PS Closed", "PS Open"]
    node_hydro = data["node_hydro"]
    node_battery = data["node_battery"]
    
    #### Parameters
    VOLL = data["VOLL"]
    deltaT = data["deltaT"]
    generators_data = data["generators_data"]
    load = data["load"]
    line_data = data["line_data"]
    battery_data = data["battery_data"]
    hydro_data = data["hydro_data"]
    dsr_data = data["dsr_data"]

    #### Variables
    # Generator investment decisions
    @variable(EVA_model, 0 <= x_new[i in generators_new_keys, generators_new[i]], Int)
    @variable(EVA_model, 0 <= x_exist[i in generators_exist_keys, generators_exist[i]], Int)
    # System variables
    @variable(EVA_model, flow[i in line_from_keys, j in line_from[i], periods])
    @variable(EVA_model, 0 <= abs_flow[i in line_from_keys, j in line_from[i], periods]) # a slack variable to model the abs value of flow in the objective function
    @variable(EVA_model, 0 <= slack_pos[nodes, periods]) # means load shedding
    @variable(EVA_model, 0 <= slack_neg[nodes, periods]) # means production shedding
    #@variable(EVA_model, 0 <= slack_pos2[nodes, periods] <= 20) # ELASTIC load shedding
    # Generator production decisions
    @variable(EVA_model, 0 <= p_new[i in generators_new_keys, generators_new[i], periods])
    @variable(EVA_model, 0 <= p_exist[i in generators_exist_keys, generators_exist[i], periods])
    @variable(EVA_model, 0 <= p_dsr[i in dsr_keys, dsr[i], periods])
    # Batteries
    @variable(EVA_model, 0 <= bv[i in node_battery, periods]) # battery volume
    @variable(EVA_model, 0 <= bc[i in node_battery, periods]) # battery charge
    @variable(EVA_model, 0 <= bd[i in node_battery, periods]) # battery discharge
    # Hydro
    @variable(EVA_model, 0 <= p_turb[h in hydro_types, i in node_hydro[h], t in periods])
    @variable(EVA_model, 0 <= p_pump[h in ps_hydro, i in node_hydro[h], t in periods])
    @variable(EVA_model, 0 <= v_head[h in hydro_types, i in node_hydro[h], t in periods])
    @variable(EVA_model, 0 <= v_tail[h in ps_hydro, i in node_hydro[h], t in periods])
    @variable(EVA_model, 0 <= s[h in hydro_types, i in node_hydro[h], t in periods])

    #### Objective - minimize total investment + operational cost
    println("Initializing objective...")
    @objective(EVA_model, Min,
        sum(x_new[i,g] * generators_data["New"][i][g]["Lumps"] * generators_data["New"][i][g]["IC"] for i in generators_new_keys for g in generators_new[i]) # cost of investing in new generators
        - sum(x_exist[i,g] * generators_data["Exist"][i][g]["Lumps"] * generators_data["Exist"][i][g]["IC"] for i in generators_exist_keys for g in generators_exist[i]) # cost avoided by retiring existing capacity
        + deltaT*(sum(p_new[i,g,t] * generators_data["New"][i][g]["OC"] for i in generators_new_keys for g in generators_new[i] for t in periods) # operational cost of new gen
        + sum(p_exist[i,g,t] * generators_data["Exist"][i][g]["OC"] for i in generators_exist_keys for g in generators_exist[i] for t in periods) # operational cost of existing gen
        + sum(p_dsr[i,g,t] * dsr_data[i][g]["Offer Price"] for i in dsr_keys for g in dsr[i] for t in periods) # operational cost of DSR
        + sum(VOLL * slack_pos[i,t] for i in nodes for t in periods) # load curtailement
    #    + sum((VOLL/(2*20)) * slack_pos2[i,t]^2 for i in nodes for t in periods) # elastic load curtailement
        + sum(abs_flow[i,j,t] * line_data[i][j]["Wheeling Charge"] for i in line_from_keys for j in line_from[i] for t in periods) # line flow charge
        + sum(s[h, i, t] * hydro_data["hydro_storage"][i][h]["Head Storage"]["Spill Penalty"] for h in hydro_types for i in node_hydro[h] for t in periods)) # cost of hydro spilling water
    )

    #### Constraints
    # Market clearign constraint
    println("Initializing MC constraint...")
    @constraint(EVA_model, MC_cons[i in nodes, t in periods],
        (i in generators_new_keys ? sum(p_new[i,g,t] for g in generators_new[i]) : 0.0) # new generator production
        + (i in generators_exist_keys ? sum(p_exist[i,g,t] for g in generators_exist[i]) : 0.0) # existing generator production
        + (i in dsr_keys ? sum(p_dsr[i,g,t] for g in dsr[i]) : 0.0) # DSR production
        + (i in node_battery ? (bd[i,t] - bc[i,t]) : 0.0) # Battery charge and discharge
        + reduce(+, [p_turb[h,i,t] for h in hydro_types if i in node_hydro[h]], init=0.0)
        - reduce(+, [p_pump[h,i,t] for h in ps_hydro if i in node_hydro[h]], init=0.0) # hydro production and consumption
        + slack_pos[i, t] - slack_neg[i, t] # load / production shedding
    #    + slack_pos2[i, t] # load elastic shedding
        == load[i][t]
        + (i in line_from_keys ? sum(flow[i, j, t] for j in line_from[i]) : 0.0) - (i in line_to_keys ? sum(flow[j, i, t] for j in line_to[i]) : 0.0)
    )

    # Generators investment constraints
    println("Initializing generators constraints...")
    @constraint(EVA_model, max_invest_new[i in generators_new_keys, g in generators_new[i]],
        x_new[i, g] <= floor(generators_data["New"][i][g]["CapaMax"]/generators_data["New"][i][g]["Lumps"])
    )

    @constraint(EVA_model, max_invest_exist[i in generators_exist_keys, g in generators_exist[i]],
        x_exist[i, g] <= floor(generators_data["Exist"][i][g]["RCapaMax"]/generators_data["Exist"][i][g]["Lumps"])
    )

    # Generators operational constraints
    @constraint(EVA_model, [i in generators_new_keys, g in generators_new[i], t in periods],
        p_new[i, g, t] <= x_new[i, g] * generators_data["New"][i][g]["Lumps"]
    )

    @constraint(EVA_model, [i in generators_exist_keys, g in generators_exist[i], t in periods],
        p_exist[i, g, t] <= generators_data["Exist"][i][g]["Rating"][t] - x_exist[i, g] * generators_data["Exist"][i][g]["Lumps"] * (generators_data["Exist"][i][g]["Rating"][t]/generators_data["Exist"][i][g]["Max Rating"])
    )

    @constraint(EVA_model, [i in generators_exist_keys, g in generators_exist[i], t in periods],
        p_exist[i, g, t] >= generators_data["Exist"][i][g]["Min Load"][t]
    )

    # DSR operational constraint
    println("Initializing DSR constraints...")
    @constraint(EVA_model, [i in dsr_keys, g in dsr[i], t in periods],
        p_dsr[i, g, t] <= dsr_data[i][g]["Offer Quantity"][t]
    )

    # Network (ATC) constraints
    println("Initializing network constraints...")
    @constraint(EVA_model, flow_min[i in line_from_keys, j in line_from[i], t in periods],
        flow[i, j, t] >= line_data[i][j]["Min Flow"][t]
    )

    @constraint(EVA_model, flow_max[i in line_from_keys, j in line_from[i], t in periods],
        flow[i, j, t] <= line_data[i][j]["Max Flow"][t]
    )

    @constraint(EVA_model, abs_flow_cons1[i in line_from_keys, j in line_from[i], t in periods],
        flow[i, j, t] <= abs_flow[i, j, t]
    )

    @constraint(EVA_model, abs_flow_cons2[i in line_from_keys, j in line_from[i], t in periods],
        -flow[i, j, t] <= abs_flow[i, j, t]
    )

    # Batteries constraints
    println("Initializing batteries constraints...")
    @constraint(EVA_model, [i in node_battery, t in periods],
        bv[i, t] <= battery_data[i]["Capacity"]
    )

    @constraint(EVA_model, [i in node_battery, t in periods],
        bc[i, t] <= battery_data[i]["Max Power"]
    )

    @constraint(EVA_model, [i in node_battery, t in periods],
        bd[i, t] <= battery_data[i]["Max Power"]
    )

    @constraint(EVA_model, [i in node_battery, t in periods; t>1],
        bv[i, t] == bv[i, t-1] + deltaT*(- bd[i, t] + bc[i, t] * battery_data[i]["Charge Efficiency"])
    )

    @constraint(EVA_model, [i in node_battery],
        bv[i, 1] == battery_data[i]["Init Volume"] + deltaT*(-bd[i, 1] + bc[i, 1] * battery_data[i]["Charge Efficiency"])
    ) # this is the initial condition

    # Hydro constraints
    println("Initializing hydro constraints...")
    @constraint(EVA_model, [h in hydro_types, i in node_hydro[h], t in periods],
        v_head[h, i, t] <= hydro_data["hydro_storage"][i][h]["Head Storage"]["Max Volume"]
    ) # head storage constraint for all hydros

    @constraint(EVA_model, [h in hydro_types, i in node_hydro[h], t in periods],
        p_turb[h, i, t] <= hydro_data["hydro"][i][h]["Rating"][t]
    ) # max turb constraint for all hydros

    @constraint(EVA_model, [i in node_hydro["Reservoir"], t in periods; t>1],
        v_head["Reservoir", i, t] == v_head["Reservoir", i, t-1]
        + deltaT*(hydro_data["hydro_storage"][i]["Reservoir"]["Head Storage"]["Natural Inflow"][t]
        - p_turb["Reservoir", i, t] - s["Reservoir", i, t])
    ) # volume expression for Reservoir

    @constraint(EVA_model, [i in node_hydro["Reservoir"]],
        v_head["Reservoir", i, 1] == hydro_data["hydro_storage"][i]["Reservoir"]["Head Storage"]["Initial Volume"]
        + deltaT*(hydro_data["hydro_storage"][i]["Reservoir"]["Head Storage"]["Natural Inflow"][1]
        - p_turb["Reservoir", i, 1] - s["Reservoir", i, 1])
    ) # volume initial condition for Reservoir

    @constraint(EVA_model, [i in node_hydro["PS Closed"], t in periods; t>1],
        v_head["PS Closed", i, t] == v_head["PS Closed", i, t-1]
        + deltaT*(p_pump["PS Closed", i, t] * hydro_data["hydro"][i]["PS Closed"]["Pump Efficiency"]
        - p_turb["PS Closed", i, t] - s["PS Closed", i, t])
    ) # volume expression for PS Closed

    @constraint(EVA_model, [i in node_hydro["PS Closed"]],
        v_head["PS Closed", i, 1] == hydro_data["hydro_storage"][i]["PS Closed"]["Head Storage"]["Initial Volume"]
        + deltaT*(p_pump["PS Closed", i, 1] * hydro_data["hydro"][i]["PS Closed"]["Pump Efficiency"]
        - p_turb["PS Closed", i, 1] - s["PS Closed", i, 1])
    ) # volume initial condition for PS Closed

    @constraint(EVA_model, [i in node_hydro["PS Open"], t in periods; t>1],
        v_head["PS Open", i, t] == v_head["PS Open", i, t-1]
        + deltaT*(hydro_data["hydro_storage"][i]["PS Open"]["Head Storage"]["Natural Inflow"][t]
        + p_pump["PS Open", i, t] * hydro_data["hydro"][i]["PS Open"]["Pump Efficiency"]
        - p_turb["PS Open", i, t] - s["PS Open", i, t])
    ) # volume expression for PS Open

    @constraint(EVA_model, [i in node_hydro["PS Open"]],
        v_head["PS Open", i, 1] == hydro_data["hydro_storage"][i]["PS Open"]["Head Storage"]["Initial Volume"]
        + deltaT*(hydro_data["hydro_storage"][i]["PS Open"]["Head Storage"]["Natural Inflow"][1]
        + p_pump["PS Open", i, 1] * hydro_data["hydro"][i]["PS Open"]["Pump Efficiency"]
        - p_turb["PS Open", i, 1] - s["PS Open", i, 1])
    ) # volume initial condition for PS Open

    @constraint(EVA_model, [h in ps_hydro, i in node_hydro[h], t in periods; t>1],
        v_tail[h, i, t] == v_tail[h, i, t-1]
        + deltaT*(- p_pump[h, i, t] * hydro_data["hydro"][i][h]["Pump Efficiency"]
        + p_turb[h, i, t])
    ) # volume expression for tail reservoir (for Pump-storage hydro)

    @constraint(EVA_model, [h in ps_hydro, i in node_hydro[h]],
        v_tail[h, i, 1] == hydro_data["hydro_storage"][i][h]["Tail Storage"]["Initial Volume"]
        + deltaT*(- p_pump[h, i, 1] * hydro_data["hydro"][i][h]["Pump Efficiency"]
        + p_turb[h, i, 1])
    ) # volume initial conditions for tail reservoir (for Pump-storage hydro)

    @constraint(EVA_model, [h in ps_hydro, i in node_hydro[h], t in periods],
        p_pump[h, i, t] <= hydro_data["hydro"][i][h]["Pump Load"][t]
    ) # contraint on pump power (for Pump-storage hydro)

    println("Model completed.")
    return EVA_model
end


function computeInvAndOpCosts_discrete(model, data)
    Inv_cost = (sum(value(model[:x_new][i,g]) * data["generators_data"]["New"][i][g]["Lumps"] * data["generators_data"]["New"][i][g]["IC"] for i in data["generators_new_keys"] for g in data["generators_new"][i])
        - sum(value(model[:x_exist][i,g]) * data["generators_data"]["Exist"][i][g]["Lumps"] * data["generators_data"]["Exist"][i][g]["IC"] for i in data["generators_exist_keys"] for g in data["generators_exist"][i]))
    Op_cost = objective_value(model) - Inv_cost
    # correct the IC cost by adding the fixed term
    Inv_cost = Inv_cost + sum(data["generators_data"]["Exist"][i][g]["Max Rating"] * data["generators_data"]["Exist"][i][g]["IC"] for i in data["generators_exist_keys"] for g in data["generators_exist"][i])
    return Dict("Investment cost" => Inv_cost, "Operational Cost"=>Op_cost)
end


# a function that compute the prices
function ipPricing(model, data)
    # Get the O'Neill prices from the dispatch model "model"
    price_model, reference_map = copy_model(model)
    set_optimizer(price_model, Gurobi.Optimizer)
    println("Computing (IP) O'Neill prices...")
    println("Fixing the integer variables...")
    # Fix the values of the binary variables
    for i in data["generators_new_keys"], g in data["generators_new"][i]
        fix(price_model[:x_new][i,g], value(model[:x_new][i,g]); force = true)
        unset_integer(price_model[:x_new][i,g])
    end
    for i in data["generators_exist_keys"], g in data["generators_exist"][i]
        fix(price_model[:x_exist][i,g], value(model[:x_exist][i,g]); force = true)
        unset_integer(price_model[:x_exist][i,g])
    end

    println("Solving the convex pricing problem")
    set_optimizer_attribute(price_model, "OutputFlag", 0)
    optimize!(price_model)
    ip_prices = dual.(price_model[:MC_cons])
    return ip_prices
end

function solve_EVA_discrete(data, initial_solution)
    println("Initializing the model...")
    start_time = time()
    EVA_model = discreteCapacityExpansionModel(data)
    if (initial_solution==Nothing) == false
        println("Setting an initial solution...")
        EVA_model = set_initial_solution(EVA_model, initial_solution)
    end
    println("Solving the model...")
    optimize!(EVA_model)
    run_time = time() - start_time
    println("Model solved in $(round(run_time)) s")
    total_costs = computeInvAndOpCosts_discrete(EVA_model, data)
    println("The total cost is:$total_costs")
    prices = ipPricing(EVA_model, data)
    println("Computing the LOC...")
    Profits, TEI = compute_loc_discrete(EVA_model, data, prices)
    LOC = Profits["LOC"]
    println("The total LOC of New units is : $(sum(LOC["New"][i][g] for i in data["generators_new_keys"] for g in data["generators_new"][i]))")
    println("The total LOC of Existing units is : $(sum(LOC["Exist"][i][g] for i in data["generators_exist_keys"] for g in data["generators_exist"][i]))")

    MIP_gap = relative_gap(EVA_model)
    println("The MIP GAP is $MIP_gap")

    return Dict("EVA_model"=>EVA_model, "run_time"=>run_time, "total_costs"=>total_costs,
    "Profits"=>Profits, "E_prices"=>prices, "TEI"=>TEI)
end

function set_initial_solution(EVA_model, initial_solution)
    for i in data["generators_new_keys"], g in data["generators_new"][i], t in data["periods"]
        fix(EVA_model[:p_new][i,g,t], initial_solution["p_new"][i][g]["$t"]; force = true)
    end
    for i in data["generators_new_keys"], g in data["generators_new"][i]
        fix(EVA_model[:x_new][i,g], initial_solution["x_new"][i][g]; force = true) #set_start_value
    end
    for i in data["generators_exist_keys"], g in data["generators_exist"][i], t in data["periods"]
        fix(EVA_model[:p_exist][i,g,t], initial_solution["p_exist"][i][g]["$t"]; force = true)
    end
    for i in data["generators_exist_keys"], g in data["generators_exist"][i]
        fix(EVA_model[:x_exist][i,g], initial_solution["x_exist"][i][g]; force = true)
    end
    return EVA_model
end
