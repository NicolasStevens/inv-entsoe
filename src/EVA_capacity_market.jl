#=
- Julia version: 1.5.3
- Author: Nicolas
- Date: 2022-09-20
=#
################################################################################
#### CAPACITY MARKET AUCTION
################################################################################
"""
Function that runs the capacity auction. The capacity price is got from the dual
of constraint :capacityConstraint.
"""
function createCapacityPriceModel(data, Cmin, E_price)
    CRM_model = Model(() -> Gurobi.Optimizer(GUROBI_ENV))
    #set_optimizer_attribute(EVA_model, "MIPGap", 1e-4)
    #### Sets
    nodes = data["nodes"]
    periods = data["periods"]
    generators_exist_keys = data["generators_exist_keys"]
    generators_exist = data["generators_exist"]
    generators_new_keys = data["generators_new_keys"]
    generators_new = data["generators_new"]

    #### Parameters
    deltaT = data["deltaT"]
    generators_data = data["generators_data"]

    #### Variables
    # Generator investment decisions
    @variable(CRM_model, 0 <= x_new[i in generators_new_keys, generators_new[i]])
    @variable(CRM_model, 0 <= x_exist[i in generators_exist_keys, generators_exist[i]])
    # Generator production decisions
    @variable(CRM_model, 0 <= p_new[i in generators_new_keys, generators_new[i], periods])
    @variable(CRM_model, 0 <= p_exist[i in generators_exist_keys, generators_exist[i], periods])

    #### Objective - minimize total investment + operational cost
    println("Initializing objective...")
    @objective(CRM_model, Min,
        sum(x_new[i,g] * generators_data["New"][i][g]["Lumps"] * generators_data["New"][i][g]["IC"] for i in generators_new_keys for g in generators_new[i])
        - sum(x_exist[i,g] * generators_data["Exist"][i][g]["Lumps"] * generators_data["Exist"][i][g]["IC"] for i in generators_exist_keys for g in generators_exist[i])
        - sum(p_new[i,g,t] * (E_price[i,t] - deltaT*generators_data["New"][i][g]["OC"]) for i in generators_new_keys for g in generators_new[i] for t in periods)
        - sum(p_exist[i,g,t] * (E_price[i,t] - deltaT*generators_data["Exist"][i][g]["OC"]) for i in generators_exist_keys for g in generators_exist[i] for t in periods)
    )

    #### Constraints
    println("Initializing the MC constraint...")
    # Market clearign constraint
    @constraint(CRM_model, capacityConstraint[i in nodes],
        (i in generators_new_keys ? sum(x_new[i, g] * generators_data["New"][i][g]["Lumps"] for g in generators_new[i]) : 0.0) # new generator capa
        - (i in generators_exist_keys ? sum(x_exist[i, g] * generators_data["Exist"][i][g]["Lumps"] for g in generators_exist[i]) : 0.0) # existing generator capa
        >= Cmin[i]
    )

    println("Initializing the other constraints...")
    # Generators investment constraints
    #@constraint(CRM_model, max_invest_new[i in generators_new_keys, g in generators_new[i]],
    #    x_new[i, g] * generators_data["New"][i][g]["Lumps"] <= generators_data["New"][i][g]["CapaMax"]
    #)
    @constraint(CRM_model, max_invest_new[i in generators_new_keys, g in generators_new[i]],
        x_new[i, g] <= floor(generators_data["New"][i][g]["CapaMax"]/generators_data["New"][i][g]["Lumps"])
    )

    #@constraint(CRM_model, max_invest_exist[i in generators_exist_keys, g in generators_exist[i]],
    #    x_exist[i, g] * generators_data["Exist"][i][g]["Lumps"] <= generators_data["Exist"][i][g]["RCapaMax"]
    #)
    @constraint(CRM_model, max_invest_exist[i in generators_exist_keys, g in generators_exist[i]],
        x_exist[i, g] <= floor(generators_data["Exist"][i][g]["RCapaMax"]/generators_data["Exist"][i][g]["Lumps"])
    )

    # Generators operational constraints
    @constraint(CRM_model, [i in generators_new_keys, g in generators_new[i], t in periods],
        p_new[i, g, t] <= x_new[i, g] * generators_data["New"][i][g]["Lumps"]
    )

    @constraint(CRM_model, [i in generators_exist_keys, g in generators_exist[i], t in periods],
        p_exist[i, g, t] <= generators_data["Exist"][i][g]["Rating"][t] - x_exist[i, g] * generators_data["Exist"][i][g]["Lumps"] * (generators_data["Exist"][i][g]["Rating"][t]/generators_data["Exist"][i][g]["Max Rating"])
    )

    @constraint(CRM_model, [i in generators_exist_keys, g in generators_exist[i], t in periods],
        p_exist[i, g, t] >= generators_data["Exist"][i][g]["Min Load"][t]
    )

    return CRM_model
end

"""
Function that runs the capacity auction. The capacity price is got from the dual
of constraint :capacityConstraint.
"""
function createCapacityQuantityModel(data, Cmin, E_price)
    CRM_model = Model(() -> Gurobi.Optimizer(GUROBI_ENV))
    #set_optimizer_attribute(EVA_model, "MIPGap", 1e-4)
    #### Sets
    nodes = data["nodes"]
    periods = data["periods"]
    generators_exist_keys = data["generators_exist_keys"]
    generators_exist = data["generators_exist"]
    generators_new_keys = data["generators_new_keys"]
    generators_new = data["generators_new"]

    #### Parameters
    deltaT = data["deltaT"]
    generators_data = data["generators_data"]

    #### Variables
    # Generator investment decisions
    @variable(CRM_model, 0 <= x_new[i in generators_new_keys, generators_new[i]], Int)
    @variable(CRM_model, 0 <= x_exist[i in generators_exist_keys, generators_exist[i]], Int)
    # Generator production decisions
    @variable(CRM_model, 0 <= p_new[i in generators_new_keys, generators_new[i], periods])
    @variable(CRM_model, 0 <= p_exist[i in generators_exist_keys, generators_exist[i], periods])

    #### Objective - minimize total investment + operational cost
    println("Initializing objective...")
    @objective(CRM_model, Min,
        sum(x_new[i,g] * generators_data["New"][i][g]["Lumps"] * generators_data["New"][i][g]["IC"] for i in generators_new_keys for g in generators_new[i])
        - sum(x_exist[i,g] * generators_data["Exist"][i][g]["Lumps"] * generators_data["Exist"][i][g]["IC"] for i in generators_exist_keys for g in generators_exist[i])
        - sum(p_new[i,g,t] * (E_price[i,t] - deltaT*generators_data["New"][i][g]["OC"]) for i in generators_new_keys for g in generators_new[i] for t in periods)
        - sum(p_exist[i,g,t] * (E_price[i,t] - deltaT*generators_data["Exist"][i][g]["OC"]) for i in generators_exist_keys for g in generators_exist[i] for t in periods)
    )

    #### Constraints
    println("Initializing the MC constraint...")
    # Market clearign constraint
    @constraint(CRM_model, capacityConstraint[i in nodes],
        (i in generators_new_keys ? sum(x_new[i, g] * generators_data["New"][i][g]["Lumps"] for g in generators_new[i]) : 0.0) # new generator capa
        - (i in generators_exist_keys ? sum(x_exist[i, g] * generators_data["Exist"][i][g]["Lumps"] for g in generators_exist[i]) : 0.0) # existing generator capa
        >= Cmin[i]
    )

    println("Initializing the other constraints...")
    # Generators investment constraints
    @constraint(CRM_model, max_invest_new[i in generators_new_keys, g in generators_new[i]],
        x_new[i, g] <= floor(generators_data["New"][i][g]["CapaMax"]/generators_data["New"][i][g]["Lumps"])
    )

    @constraint(CRM_model, max_invest_exist[i in generators_exist_keys, g in generators_exist[i]],
        x_exist[i, g] <= floor(generators_data["Exist"][i][g]["RCapaMax"]/generators_data["Exist"][i][g]["Lumps"])
    )

    # Generators operational constraints
    @constraint(CRM_model, [i in generators_new_keys, g in generators_new[i], t in periods],
        p_new[i, g, t] <= x_new[i, g] * generators_data["New"][i][g]["Lumps"]
    )

    @constraint(CRM_model, [i in generators_exist_keys, g in generators_exist[i], t in periods],
        p_exist[i, g, t] <= generators_data["Exist"][i][g]["Rating"][t] - x_exist[i, g] * generators_data["Exist"][i][g]["Lumps"] * (generators_data["Exist"][i][g]["Rating"][t]/generators_data["Exist"][i][g]["Max Rating"])
    )

    @constraint(CRM_model, [i in generators_exist_keys, g in generators_exist[i], t in periods],
        p_exist[i, g, t] >= generators_data["Exist"][i][g]["Min Load"][t]
    )

    return CRM_model
end

"""
Function that solves the capacity pricing model in which only the capacity
price is computed.
"""
function solveCapacityPriceModel(data, Cmin, E_price)
    println("Solving the capacity auction to determine the capacity prices...")
    CRM_model = createCapacityPriceModel(data, Cmin, E_price)
    println("Solving the capacity auction...")
    optimize!(CRM_model)
    Capa_prices = dual.(CRM_model[:capacityConstraint])

    # test (to be deleted after)
    println("Solving the discrete CRM to compute quantities...")
    CRM2_model = createCapacityQuantityModel(data, Cmin, E_price)
    optimize!(CRM2_model)
    x_new = Dict(i=>Dict(g=>value(CRM2_model[:x_new][i,g]) for g in data["generators_new"][i]) for i in data["generators_new_keys"])
    x_exist = Dict(i=>Dict(g=>value(CRM2_model[:x_exist][i,g]) for g in data["generators_exist"][i]) for i in data["generators_exist_keys"])
    open("x_newCRM.json","w") do f
        JSON.print(f, x_new)
    end
    open("x_existCRM.json","w") do f
        JSON.print(f, x_exist)
    end

    return Capa_prices
end


################################################################################
#### LOST OPPORTUITY COSTS OF THE MARKET AGENTS UNDER CAPACITY PRICES
################################################################################
"""
Function that creates the model for agent (i,g) of the private profit
    maximization problem with a uniform capacity price.
"""
function ProfitMaxModelDiscrete_CRM(data, g_type, i, g, E_price, C_price)
    model = Model(() -> Gurobi.Optimizer(GUROBI_ENV))
    #set_optimizer_attribute(EVA_model, "MIPGap", 1e-4)
    #### Sets
    nodes = data["nodes"]
    periods = data["periods"]
    generators_exist_keys = data["generators_exist_keys"]
    generators_exist = data["generators_exist"]
    generators_new_keys = data["generators_new_keys"]
    generators_new = data["generators_new"]

    #### Parameters
    deltaT = data["deltaT"]
    generators_data = data["generators_data"]

    if g_type=="New"
        #### Variables
        @variable(model, 0 <= x_new, Int)
        @variable(model, 0 <= p_new[periods])

        #### Objective - maximize LT profit (icluding investment and operational cost)
        # since the E_price already accounts for the duration, it should not be
        # multiplied by deltaT. While OC should be.
        @objective(model, Max,
            sum(p_new[t] * (E_price[i,t] - deltaT*generators_data["New"][i][g]["OC"]) for t in periods)
            + x_new * generators_data["New"][i][g]["Lumps"] * C_price[i]
            - x_new * generators_data["New"][i][g]["Lumps"] * generators_data["New"][i][g]["IC"]
        )

        #### Constraints
        @constraint(model, max_invest_new,
            x_new * generators_data["New"][i][g]["Lumps"] <= generators_data["New"][i][g]["CapaMax"]
        )

        @constraint(model, [t in periods],
            p_new[t] <= x_new * generators_data["New"][i][g]["Lumps"]
        )
    else
        #### Variables
        @variable(model, 0 <= x_exist, Int)
        @variable(model, 0 <= p_exist[periods])

        #### Objective - maximize LT profit (icluding investment and operational cost)
        @objective(model, Max,
            sum(p_exist[t] * (E_price[i,t] - deltaT * generators_data["Exist"][i][g]["OC"]) for t in periods)
            - x_exist * generators_data["Exist"][i][g]["Lumps"] * C_price[i]
            + x_exist * generators_data["Exist"][i][g]["Lumps"] * generators_data["Exist"][i][g]["IC"]
        )

        #### Constraints
        @constraint(model, max_invest_exist,
            x_exist * generators_data["Exist"][i][g]["Lumps"] <= generators_data["Exist"][i][g]["RCapaMax"]
        )

        @constraint(model, [t in periods],
            p_exist[t] <= generators_data["Exist"][i][g]["Rating"][t] - x_exist * generators_data["Exist"][i][g]["Lumps"] * (generators_data["Exist"][i][g]["Rating"][t]/generators_data["Exist"][i][g]["Max Rating"])
        )

        @constraint(model, [t in periods],
            p_exist[t] >= generators_data["Exist"][i][g]["Min Load"][t]
        )
    end

    return model
end

"""
Function that computes the max private profit with a uniform capacity price.
"""
function compute_maxprofit_discrete_CRM(data, E_price, C_price)
    max_profit_new = Dict(i => Dict(g => 0.0 for g in data["generators_new"][i]) for i in data["generators_new_keys"])
    max_profit_x_new = Dict(i => Dict(g => 0.0 for g in data["generators_new"][i]) for i in data["generators_new_keys"])
    for i in data["generators_new_keys"]
        for g in data["generators_new"][i]
            model_max_profit = ProfitMaxModelDiscrete_CRM(data, "New", i, g, E_price, C_price)
            set_optimizer_attribute(model_max_profit, "OutputFlag", 0)
            optimize!(model_max_profit)
            max_profit_new[i][g] = objective_value(model_max_profit)
            max_profit_x_new[i][g] = copy(value(model_max_profit[:x_new]))
        end
    end
    max_profit_exist = Dict(i => Dict(g => 0.0 for g in data["generators_exist"][i]) for i in data["generators_exist_keys"])
    max_profit_x_exist = Dict(i => Dict(g => 0.0 for g in data["generators_exist"][i]) for i in data["generators_exist_keys"])
    for i in data["generators_exist_keys"]
        for g in data["generators_exist"][i]
            model_max_profit = ProfitMaxModelDiscrete_CRM(data, "Exist", i, g, E_price, C_price)
            set_optimizer_attribute(model_max_profit, "OutputFlag", 0)
            optimize!(model_max_profit)
            max_profit_exist[i][g] = objective_value(model_max_profit) - data["generators_data"]["Exist"][i][g]["Max Rating"] * (data["generators_data"]["Exist"][i][g]["IC"] - C_price[i])
            max_profit_x_exist[i][g] = copy(value(model_max_profit[:x_exist]))
        end
    end

    return Dict("New"=>max_profit_new, "Exist"=>max_profit_exist, "max_profit_x_new"=>max_profit_x_new, "max_profit_x_exist"=>max_profit_x_exist)
end

"""
Function that computes the as-cleared profit with a uniform capacity price.
"""
function compute_asclearedprofit_discrete_CRM(x_new, x_exist, p_new, p_exist, data, E_price, C_price)
    periods = data["periods"]
    generators_exist_keys = data["generators_exist_keys"]
    generators_exist = data["generators_exist"]
    generators_new_keys = data["generators_new_keys"]
    generators_new = data["generators_new"]
    generators_data = data["generators_data"]
    deltaT = data["deltaT"]

    as_cleared_profit_new = Dict(i=>Dict(
        g => (sum(p_new[i,g,t] * (E_price[i,t] - deltaT * generators_data["New"][i][g]["OC"]) for t in periods)
        - x_new[i,g] * generators_data["New"][i][g]["Lumps"] * generators_data["New"][i][g]["IC"]
        + x_new[i,g] * generators_data["New"][i][g]["Lumps"] * C_price[i])
        for g in generators_new[i]) for i in generators_new_keys)

    as_cleared_profit_exist = Dict(i=>Dict(
        g => (sum(p_exist[i,g,t] * (E_price[i,t] - deltaT * generators_data["Exist"][i][g]["OC"]) for t in periods)
        - (generators_data["Exist"][i][g]["Max Rating"] - x_exist[i,g] * generators_data["Exist"][i][g]["Lumps"]) * generators_data["Exist"][i][g]["IC"]
        + (generators_data["Exist"][i][g]["Max Rating"] - x_exist[i,g] * generators_data["Exist"][i][g]["Lumps"]) * C_price[i])
        for g in generators_exist[i]) for i in generators_exist_keys)

    return Dict("New"=>as_cleared_profit_new, "Exist"=>as_cleared_profit_exist)
end

"""
Function that computes the LOC per agent for a pricing scheme that includes both
    an energy and a capacity price.
"""
function compute_loc_discrete_CRM(x_new, x_exist, p_new, p_exist, data, E_price, C_price)
    println("Computing the agents Lost Opportunity Costs with both Energy and Capacity prices...")
    println("Computing the max profit...")
    start_time = time()
    max_profit = compute_maxprofit_discrete_CRM(data, E_price, C_price)
    elapsed = time() - start_time
    println("solved in $elapsed s.")
    println("Computing the as-cleared profit...")
    start_time = time()

    as_cleared_profit = compute_asclearedprofit_discrete_CRM(x_new, x_exist, p_new, p_exist, data, E_price, C_price)
    elapsed = time() - start_time
    println("solved in $elapsed s.")

    loc_new = Dict(i=>Dict(g=>(max_profit["New"][i][g] - as_cleared_profit["New"][i][g]) for g in data["generators_new"][i]) for i in data["generators_new_keys"])
    loc_exist = Dict(i=>Dict(g=>(max_profit["Exist"][i][g] - as_cleared_profit["Exist"][i][g]) for g in data["generators_exist"][i]) for i in data["generators_exist_keys"])

    TEI = compute_tei(data, x_new, x_exist, max_profit["max_profit_x_new"], max_profit["max_profit_x_exist"], loc_new, loc_exist)
    println("Total Excess Investment is: $TEI")

    return Dict("LOC"=>Dict("New"=>loc_new, "Exist"=>loc_exist),"As-Cleared Profit"=>as_cleared_profit, "Max Profit"=>max_profit), TEI
end


"""
The function computes the total excess investment (the difference between investment decisions
    made by individuals decentrally and the ones made by the central agent).
"""
function compute_tei(data, central_x_new, central_x_exist, dec_x_new, dec_x_exist, loc_new, loc_exist)
    TEI = 0.0
    for i in data["generators_new_keys"]
        for g in data["generators_new"][i]
            if loc_new[i][g]>0.1 # if the LOC=0 it means the centralized investment decisions are also decentralized decisions.
                TEI = TEI + (dec_x_new[i][g] - central_x_new[i,g])*data["generators_data"]["New"][i][g]["Lumps"]
            end
        end
    end
    for i in data["generators_exist_keys"]
        for g in data["generators_exist"][i]
            if loc_exist[i][g]>0.1 # if the LOC=0 it means the centralized investment decisions are also decentralized decisions.
                TEI = TEI + (central_x_exist[i,g] - dec_x_exist[i][g])*data["generators_data"]["Exist"][i][g]["Lumps"]
            end
        end
    end

    return TEI
end


################################################################################
#### GENERAL FUNCTIONS
################################################################################
"""
Function that computes the optimum Cmin target: Cmin is set to the optimum
investment decisions. There is one Cmin target per node.
"""
function compute_Cmin(x_new, x_exist, data)
    generators_exist_keys = data["generators_exist_keys"]
    generators_exist = data["generators_exist"]
    generators_new_keys = data["generators_new_keys"]
    generators_new = data["generators_new"]
    generators_data = data["generators_data"]
    # retrieve the optimum investment decisions
    #x_new = value.(model[:x_new])
    #x_exist = value.(model[:x_exist])
    # compute the Cmin per bidding zone
    Cmin = Dict(i=>((i in generators_new_keys ? sum(x_new[i, g] * generators_data["New"][i][g]["Lumps"] for g in generators_new[i]) : 0.0)
    - (i in generators_exist_keys ? sum(x_exist[i, g] * generators_data["Exist"][i][g]["Lumps"] for g in generators_exist[i]) : 0.0))
    for i in data["nodes"])
    return Cmin
end

"""
Function that executes the whole serie of actions: it solves the discrete
investment problem, compute the IP prices, set Cmin, compute the capacity price
and then compute the related LOC and profits of the agents.
"""
function solve_EVA_discrete_CRM(data, initial_solution)
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
    E_price = ipPricing(EVA_model, data)
    Cmin = compute_Cmin(value.(EVA_model[:x_new]), value.(EVA_model[:x_exist]), data)
    println("The capacity requirement Cmin = $Cmin")
    C_price = solveCapacityPriceModel(data, Cmin, E_price)
    println("the capacity prices are: $C_price")
    println("Computing the LOC...")

    Profits, TEI = compute_loc_discrete_CRM(value.(EVA_model[:x_new]), value.(EVA_model[:x_exist]), value.(EVA_model[:p_new]), value.(EVA_model[:p_exist]), data, E_price, C_price)
    LOC = Profits["LOC"]
    println("The total LOC of New units is : $(sum(LOC["New"][i][g] for i in data["generators_new_keys"] for g in data["generators_new"][i]))")
    println("The total LOC of Existing units is : $(sum(LOC["Exist"][i][g] for i in data["generators_exist_keys"] for g in data["generators_exist"][i]))")

    return Dict("EVA_model"=>EVA_model, "run_time"=>run_time, "total_costs"=>total_costs,
    "Profits"=>Profits, "C_prices"=>C_price, "E_prices"=>E_price, "TEI"=>TEI)
end


"""
Function that solve the CRM starting from the results of the discrete investment problem.
"""
function solve_EVA_discrete_CRM_only(data, discrete_solution_path)
    println("Loading the discrete solution...")
    # load discrete solution 
    x_new_loaded = JSON.parsefile(discrete_solution_path*"x_new.json")
    x_exist_loaded = JSON.parsefile(discrete_solution_path*"x_exist.json")
    p_new_loaded = JSON.parsefile(discrete_solution_path*"p_new.json")
    p_exist_loaded = JSON.parsefile(discrete_solution_path*"p_exist.json")
    # load IP price
    E_price_loaded = JSON.parsefile(discrete_solution_path*"E_price.json")
    # convert it to Axis Array type
    x_new_convert = Dict((i,g)=>x_new_loaded[i][g] for i in keys(x_new_loaded) for g in keys(x_new_loaded[i]))
    x_exist_convert = Dict((i,g)=>x_exist_loaded[i][g] for i in keys(x_exist_loaded) for g in keys(x_exist_loaded[i]))
    p_new_convert = Dict((i,g,t)=>p_new_loaded[i][g]["$t"] for i in keys(p_new_loaded) for g in keys(p_new_loaded[i]) for t in data["periods"])
    p_exist_convert = Dict((i,g,t)=>p_exist_loaded[i][g]["$t"] for i in keys(p_exist_loaded) for g in keys(p_exist_loaded[i]) for t in data["periods"])
    E_price_convert = Dict((i,t)=>E_price_loaded[i]["$t"] for i in keys(E_price_loaded) for t in data["periods"])
    x_new = Containers.SparseAxisArray(x_new_convert)
    x_exist = Containers.SparseAxisArray(x_exist_convert)
    p_new = Containers.SparseAxisArray(p_new_convert)
    p_exist = Containers.SparseAxisArray(p_exist_convert)
    E_price = Containers.SparseAxisArray(E_price_convert)
    
    Cmin = compute_Cmin(x_new, x_exist, data)
    println("The capacity requirement Cmin = $Cmin")
    C_price = solveCapacityPriceModel(data, Cmin, E_price)
    println("the capacity prices are: $C_price")
    println("Computing the LOC...")
    Profits, TEI = compute_loc_discrete_CRM(x_new, x_exist, p_new, p_exist, data, E_price, C_price)
    LOC = Profits["LOC"]
    println("The total LOC of New units is : $(sum(LOC["New"][i][g] for i in data["generators_new_keys"] for g in data["generators_new"][i]))")
    println("The total LOC of Existing units is : $(sum(LOC["Exist"][i][g] for i in data["generators_exist_keys"] for g in data["generators_exist"][i]))")

    return Dict("EVA_model"=>Nothing, "total_costs"=>Nothing, "run_time"=>Nothing, "Profits"=>Profits, 
        "C_prices"=>C_price, "E_prices"=>E_price, "TEI"=>TEI, "x_new"=>x_new, "x_exist"=>x_exist)
end


"""
Function that solve the CRM starting from the results of the discrete investment problem.

The difference is that this function uses the x_new and x_exist from the national estimates to 
    compute the capacity target.
"""
function solve_EVA_discrete_CRM_only2(data, discrete_solution_path, Cmin_solution_path)
    println("Loading the discrete solution...")
    # load discrete solution 
    x_new_loaded = JSON.parsefile(discrete_solution_path*"x_new.json")
    x_exist_loaded = JSON.parsefile(discrete_solution_path*"x_exist.json")
    p_new_loaded = JSON.parsefile(discrete_solution_path*"p_new.json")
    p_exist_loaded = JSON.parsefile(discrete_solution_path*"p_exist.json")
    # load IP price
    E_price_loaded = JSON.parsefile(discrete_solution_path*"E_price.json")
    # convert it to Axis Array type
    x_new_convert = Dict((i,g)=>x_new_loaded[i][g] for i in keys(x_new_loaded) for g in keys(x_new_loaded[i]))
    x_exist_convert = Dict((i,g)=>x_exist_loaded[i][g] for i in keys(x_exist_loaded) for g in keys(x_exist_loaded[i]))
    p_new_convert = Dict((i,g,t)=>p_new_loaded[i][g]["$t"] for i in keys(p_new_loaded) for g in keys(p_new_loaded[i]) for t in data["periods"])
    p_exist_convert = Dict((i,g,t)=>p_exist_loaded[i][g]["$t"] for i in keys(p_exist_loaded) for g in keys(p_exist_loaded[i]) for t in data["periods"])
    E_price_convert = Dict((i,t)=>E_price_loaded[i]["$t"] for i in keys(E_price_loaded) for t in data["periods"])
    x_new = Containers.SparseAxisArray(x_new_convert)
    x_exist = Containers.SparseAxisArray(x_exist_convert)
    p_new = Containers.SparseAxisArray(p_new_convert)
    p_exist = Containers.SparseAxisArray(p_exist_convert)
    E_price = Containers.SparseAxisArray(E_price_convert)

    x_new_cmin = JSON.parsefile(Cmin_solution_path*"x_new.json")
    x_exist_cmin = JSON.parsefile(Cmin_solution_path*"x_exist.json")
    x_new_cmin_convert = Dict((i,g)=>x_new_cmin[i][g] for i in keys(x_new_cmin) for g in keys(x_new_cmin[i]))
    x_exist_cmin_convert = Dict((i,g)=>x_exist_cmin[i][g] for i in keys(x_exist_cmin) for g in keys(x_exist_cmin[i]))
    x_new_cmin = Containers.SparseAxisArray(x_new_cmin_convert)
    x_exist_cmin = Containers.SparseAxisArray(x_exist_cmin_convert)
    
    Cmin = compute_Cmin(x_new_cmin, x_exist_cmin, data)
    println("The capacity requirement Cmin = $Cmin")
    C_price = solveCapacityPriceModel(data, Cmin, E_price)
    println("the capacity prices are: $C_price")
    println("Computing the LOC...")
    Profits, TEI = compute_loc_discrete_CRM(x_new, x_exist, p_new, p_exist, data, E_price, C_price)
    LOC = Profits["LOC"]
    println("The total LOC of New units is : $(sum(LOC["New"][i][g] for i in data["generators_new_keys"] for g in data["generators_new"][i]))")
    println("The total LOC of Existing units is : $(sum(LOC["Exist"][i][g] for i in data["generators_exist_keys"] for g in data["generators_exist"][i]))")

    return Dict("EVA_model"=>Nothing, "total_costs"=>Nothing, "run_time"=>Nothing, "Profits"=>Profits, 
        "C_prices"=>C_price, "E_prices"=>E_price, "TEI"=>TEI, "x_new"=>x_new, "x_exist"=>x_exist)
end
