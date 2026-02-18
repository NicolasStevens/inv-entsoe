#=
dispatch_problem:
- Julia version: 1.5.3
- Author: Nicolas
- Date: 2022-09-13
=#

function ProfitMaxModel(data, g_type, i, g, price)
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
        @variable(model, 0 <= x_new)
        @variable(model, 0 <= p_new[periods])

        #### Objective - maximize LT profit (icluding investment and operational cost)
        @objective(model, Max,
            sum(p_new[t] * (price[i,t] - deltaT*generators_data["New"][i][g]["OC"]) for t in periods)
            - x_new * generators_data["New"][i][g]["IC"]
        )

        #### Constraints
        @constraint(model, max_invest_new,
            x_new <= generators_data["New"][i][g]["CapaMax"]
        )

        @constraint(model, [t in periods],
            p_new[t] <= x_new
        )
    else
        #### Variables
        @variable(model, 0 <= x_exist)
        @variable(model, 0 <= p_exist[periods])

        #### Objective - maximize LT profit (icluding investment and operational cost)
        @objective(model, Max,
            sum(p_exist[t] * (price[i,t] - deltaT * generators_data["Exist"][i][g]["OC"]) for t in periods)
            + x_exist * generators_data["Exist"][i][g]["IC"]
        )

        #### Constraints
        @constraint(model, max_invest_exist,
            x_exist <= generators_data["Exist"][i][g]["RCapaMax"]
        )

        @constraint(model, [t in periods],
            p_exist[t] <= generators_data["Exist"][i][g]["Rating"][t] - x_exist * (generators_data["Exist"][i][g]["Rating"][t]/generators_data["Exist"][i][g]["Max Rating"])
        )

        @constraint(model, [t in periods],
            p_exist[t] >= generators_data["Exist"][i][g]["Min Load"][t]
        )
    end

    return model
end

function compute_maxprofit(model, data, price)
    max_profit_new = Dict(i => Dict(g => 0.0 for g in data["generators_new"][i]) for i in data["generators_new_keys"])
    for i in data["generators_new_keys"]
        for g in data["generators_new"][i]
            model_max_profit = ProfitMaxModel(data, "New", i, g, price)
            set_optimizer_attribute(model_max_profit, "OutputFlag", 0)
            optimize!(model_max_profit)
            max_profit_new[i][g] = objective_value(model_max_profit)
        end
    end
    max_profit_exist = Dict(i => Dict(g => 0.0 for g in data["generators_exist"][i]) for i in data["generators_exist_keys"])
    for i in data["generators_exist_keys"]
        for g in data["generators_exist"][i]
            model_max_profit = ProfitMaxModel(data, "Exist", i, g, price)
            set_optimizer_attribute(model_max_profit, "OutputFlag", 0)
            optimize!(model_max_profit)
            # note that we include, in the max profit, the fixed term of the fixed costs
            max_profit_exist[i][g] = objective_value(model_max_profit) - data["generators_data"]["Exist"][i][g]["Max Rating"] * data["generators_data"]["Exist"][i][g]["IC"]
        end
    end

    return Dict("New"=>max_profit_new, "Exist"=>max_profit_exist)
end


function compute_asclearedprofit(model, data, price)
    periods = data["periods"]
    generators_exist_keys = data["generators_exist_keys"]
    generators_exist = data["generators_exist"]
    generators_new_keys = data["generators_new_keys"]
    generators_new = data["generators_new"]
    generators_data = data["generators_data"]
    deltaT = data["deltaT"]

    x_new = value.(model[:x_new])
    x_exist = value.(model[:x_exist])
    p_new = value.(model[:p_new])
    p_exist = value.(model[:p_exist])

    as_cleared_profit_new = Dict(i=>Dict(
        g => (sum(p_new[i,g,t] * (price[i,t] - deltaT * generators_data["New"][i][g]["OC"]) for t in periods) - x_new[i,g] * generators_data["New"][i][g]["IC"])
        for g in generators_new[i]) for i in generators_new_keys)

    as_cleared_profit_exist = Dict(i=>Dict(
        g => (sum(p_exist[i,g,t] * (price[i,t] - deltaT * generators_data["Exist"][i][g]["OC"]) for t in periods)
        - (generators_data["Exist"][i][g]["Max Rating"] - x_exist[i,g]) * generators_data["Exist"][i][g]["IC"])
        for g in generators_exist[i]) for i in generators_exist_keys)

    return Dict("New"=>as_cleared_profit_new, "Exist"=>as_cleared_profit_exist)
end

function compute_loc(model, data, price)
    println("Computing the agents Lost Opportunity Costs...")
    println("Computing the max profit...")
    start_time = time()
    max_profit = compute_maxprofit(model, data, price)
    elapsed = time() - start_time
    println("solved in $elapsed s.")
    println("Computing the as-cleared profit...")
    start_time = time()
    as_cleared_profit = compute_asclearedprofit(model, data, price)
    elapsed = time() - start_time
    println("solved in $elapsed s.")

    loc_new = Dict(i=>Dict(g=>(max_profit["New"][i][g] - as_cleared_profit["New"][i][g]) for g in data["generators_new"][i]) for i in data["generators_new_keys"])
    loc_exist = Dict(i=>Dict(g=>(max_profit["Exist"][i][g] - as_cleared_profit["Exist"][i][g]) for g in data["generators_exist"][i]) for i in data["generators_exist_keys"])

    return Dict("LOC"=>Dict("New"=>loc_new, "Exist"=>loc_exist),"As-Cleared Profit"=>as_cleared_profit, "Max Profit"=>max_profit)
end
