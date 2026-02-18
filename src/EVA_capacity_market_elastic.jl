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
This auction is with an ELASTIC capacity demand curve (instead of an inelastic capacity requierement)
"""
function createCapacityPriceModelElastic(data, Cmin, E_price, save_path="")
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

    # Capacity demand curve characteristics
    RCC = generators_data["New"]["BE00"]["Gas/OCGT new"]["IC"] # this is the peaking unit investment cost (OCGT investment cost)
    C1 = Dict(i => 1*Cmin[i] for i in nodes)
    C2 = Cmin
    C3 =  Dict(i => 1*Cmin[i] for i in nodes)
    a2 = Dict()
    a3 = Dict()
    b2 = 2*RCC
    b3 = RCC
    for i in nodes
        if C1[i] != C2[i]
            a2[i] = -RCC/(2*(C2[i]-C1[i]))
            a3[i] = -RCC/(2*(C3[i]-C2[i]))
        else
            a2[i] = 0.0
            a3[i] = 0.0
        end
    end
    println("Drawing some of the capacity demand curves")
    drawCapaDemandCurve("BE00", data, deltaT, E_price, C1, C2, C3, RCC, 1, save_path)
    drawCapaDemandCurve("ES00", data, deltaT, E_price, C1, C2, C3, RCC, 1, save_path)
    drawCapaDemandCurve("ITSA", data, deltaT, E_price, C1, C2, C3, RCC, 1, save_path)
    drawCapaDemandCurve("IE00", data, deltaT, E_price, C1, C2, C3, RCC, 1, save_path)
    #drawCapaDemandCurve("PT00", data, deltaT, E_price, C1, C2, C3, RCC, 1, save_path)

    #### Variables
    # Generator investment decisions
    @variable(CRM_model, 0 <= x_new[i in generators_new_keys, generators_new[i]])
    @variable(CRM_model, 0 <= x_exist[i in generators_exist_keys, generators_exist[i]])
    # Generator production decisions
    @variable(CRM_model, 0 <= p_new[i in generators_new_keys, generators_new[i], periods])
    @variable(CRM_model, 0 <= p_exist[i in generators_exist_keys, generators_exist[i], periods])

    # Demand curve variables
    @variable(CRM_model, 0 <= y1[i in nodes] <= C1[i])
    @variable(CRM_model, 0 <= y2[i in nodes] <= C2[i]-C1[i])
    @variable(CRM_model, 0 <= y3[i in nodes] <= C3[i]-C2[i])

    #### Objective - minimize total investment + operational cost
    println("Initializing objective...")
    @objective(CRM_model, Max,
        # Demand curve valuation
        sum(2*RCC*y1[i] + a2[i]*y2[i]^2 + b2*y2[i] + a3[i]*y3[i]^2 + b3*y3[i] for i in nodes)
        # Supply curve cost
        - sum(x_new[i,g] * generators_data["New"][i][g]["Lumps"] * generators_data["New"][i][g]["IC"] for i in generators_new_keys for g in generators_new[i])
        + sum(x_exist[i,g] * generators_data["Exist"][i][g]["Lumps"] * generators_data["Exist"][i][g]["IC"] for i in generators_exist_keys for g in generators_exist[i])
        + sum(p_new[i,g,t] * (E_price[i,t] - deltaT*generators_data["New"][i][g]["OC"]) for i in generators_new_keys for g in generators_new[i] for t in periods)
        + sum(p_exist[i,g,t] * (E_price[i,t] - deltaT*generators_data["Exist"][i][g]["OC"]) for i in generators_exist_keys for g in generators_exist[i] for t in periods)
    )

    #### Constraints
    println("Initializing the MC constraint...")
    # Market clearign constraint
    @constraint(CRM_model, capacityConstraint[i in nodes],
        (i in generators_new_keys ? sum(x_new[i, g] * generators_data["New"][i][g]["Lumps"] for g in generators_new[i]) : 0.0) # new generator capa
        + (i in generators_exist_keys ? sum(generators_data["Exist"][i][g]["Max Rating"] - x_exist[i, g] * generators_data["Exist"][i][g]["Lumps"] for g in generators_exist[i]) : 0.0) # existing generator capa
        >= y1[i] + y2[i] + y3[i]
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
Function that solves the capacity pricing model in which only the capacity
price is computed.
"""
function solveCapacityPriceModelElastic(data, Cmin, E_price, save_path="")
    println("Solving the capacity auction to determine the capacity prices...")
    CRM_model = createCapacityPriceModelElastic(data, Cmin, E_price, save_path)
    println("Solving the capacity auction...")
    optimize!(CRM_model)
    Capa_prices = dual.(CRM_model[:capacityConstraint])
    return Capa_prices
end


################################################################################
#### GENERAL FUNCTIONS
################################################################################
"""
Function that computes the optimum Cmin target: Cmin is set to the optimum
investment decisions. There is one Cmin target per node.
Here the Cmin is computed such that it is always positive
"""
function compute_Cmin_Elastic(x_new, x_exist, data)
    generators_exist_keys = data["generators_exist_keys"]
    generators_exist = data["generators_exist"]
    generators_new_keys = data["generators_new_keys"]
    generators_new = data["generators_new"]
    generators_data = data["generators_data"]
    
    Cmin = Dict(i=>((i in generators_new_keys ? sum(x_new[i, g] * generators_data["New"][i][g]["Lumps"] for g in generators_new[i]) : 0.0)
    + (i in generators_exist_keys ? sum(generators_data["Exist"][i][g]["Max Rating"] - x_exist[i, g] * generators_data["Exist"][i][g]["Lumps"] for g in generators_exist[i]) : 0.0))
    for i in data["nodes"])
    return Cmin
end


function drawCapaDemandCurve(zone, data, deltaT, E_price, C1, C2, C3, RCC, save_fig=0, save_path="")
    println("Drawing $zone capacity demand curve")
    generators_exist = data["generators_exist"][zone]
    generators_new = data["generators_new"][zone]
    generators_data = data["generators_data"]
    periods = data["periods"]
    
    Q = []
    P = []
    # New investments
    min_rel_bid = 0.0
    for g in generators_new
        bid_price = generators_data["New"][zone][g]["IC"] - sum(max(0.0, E_price[zone,t] - deltaT*generators_data["New"][zone][g]["OC"]) for t in periods)
        bid_quantity = floor(generators_data["New"][zone][g]["CapaMax"]/generators_data["New"][zone][g]["Lumps"])*generators_data["New"][zone][g]["Lumps"]
        append!(P, bid_price)
        append!(Q, bid_quantity)
        if (bid_price < min_rel_bid) min_rel_bid=bid_price end
    end
    # Existing investments
    for g in generators_exist
        # inelastic part
        bid_price = -1e5
        bid_quantity = generators_data["Exist"][zone][g]["Max Rating"] - floor(generators_data["Exist"][zone][g]["RCapaMax"]/generators_data["Exist"][zone][g]["Lumps"])*generators_data["Exist"][zone][g]["Lumps"]
        append!(P, bid_price)
        append!(Q, bid_quantity)

        # elastic part
        bid_price = generators_data["Exist"][zone][g]["IC"] - sum(max(0.0, E_price[zone,t] - deltaT*generators_data["Exist"][zone][g]["OC"]) for t in periods)
        bid_quantity = floor(generators_data["Exist"][zone][g]["RCapaMax"]/generators_data["Exist"][zone][g]["Lumps"])*generators_data["Exist"][zone][g]["Lumps"]
        if bid_quantity>0.1
            append!(P, bid_price)
            append!(Q, bid_quantity)
            if (bid_price < min_rel_bid) min_rel_bid=bid_price end
        end
    end
    println(Q)
    println(P)
    sorted_index = sortperm(P)
    # Plot the demand curve
    plot(left_margin = 5Plots.mm, top_margin = 5Plots.mm, bottom_margin = 5Plots.mm, xtickfontsize=14, 
    ytickfontsize=14, xguidefontsize=14, yguidefontsize=14,legendfontsize=12, titlefontsize=14, 
    ylim=(min_rel_bid-1000,2*RCC+1000))
    plot!([0, C1[zone]], [2*RCC, 2*RCC],  line=(true, 5), marker=:circle, markersize=4, legend=false, linecolor=palette(:tab10)[1], markercolor=palette(:tab10)[1])
    plot!([C1[zone], C2[zone]], [2*RCC, RCC],  line=(true, 5), marker=:circle, markersize=4, legend=false, linecolor=palette(:tab10)[1], markercolor=palette(:tab10)[1])
    plot!([C2[zone], C3[zone]], [RCC, 0], line=(true, 5), marker=:circle, markersize=4, legend=false, linecolor=palette(:tab10)[1], markercolor=palette(:tab10)[1])
    # Plot the bids
    q_init = 0.0
    for i in 1:length(sorted_index)
        if i==1
            plot!([q_init, Q[sorted_index[i]]], [P[sorted_index[i]], P[sorted_index[i]]],  line=(true, 5), marker=:circle, markersize=4, legend=false, linecolor=palette(:tab10)[2], markercolor=palette(:tab10)[2])
            q_init = q_init + Q[sorted_index[i]]
        else
            plot!([q_init, q_init], [P[sorted_index[i-1]], P[sorted_index[i]]],  line=(true, 5), marker=:circle, markersize=4, legend=false, linecolor=palette(:tab10)[2], markercolor=palette(:tab10)[2])
            plot!([q_init, q_init+Q[sorted_index[i]]], [P[sorted_index[i]], P[sorted_index[i]]],  line=(true, 5), marker=:circle, markersize=4, legend=false, linecolor=palette(:tab10)[2], markercolor=palette(:tab10)[2])
            q_init = q_init + Q[sorted_index[i]]
        end
    end

    xlabel!("Demand [MW]")
    ylabel!("V(y)")
    title!("Capacity Demand Curve")
    if save_fig == 1
       savefig("$(save_path)CapaDemandCurve$zone.pdf") 
    end
    plot!()
end


"""
Function that solve the CRM starting from the results of the discrete investment problem.
The function compute the CRM with ELASTIC capacity demand curve
"""
function solve_EVA_discrete_CRM_Elastic_only(data, discrete_solution_path, save_path="")
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
    
    Cmin = compute_Cmin_Elastic(x_new, x_exist, data)
    println("The capacity requirement Cmin = $Cmin")
    C_price = solveCapacityPriceModelElastic(data, Cmin, E_price, save_path)
    println("the capacity prices are: $C_price")
    println("Computing the LOC...")
    Profits, TEI = compute_loc_discrete_CRM(x_new, x_exist, p_new, p_exist, data, E_price, C_price)
    LOC = Profits["LOC"]
    println("The total LOC of New units is : $(sum(LOC["New"][i][g] for i in data["generators_new_keys"] for g in data["generators_new"][i]))")
    println("The total LOC of Existing units is : $(sum(LOC["Exist"][i][g] for i in data["generators_exist_keys"] for g in data["generators_exist"][i]))")

    return Dict("EVA_model"=>Nothing, "total_costs"=>Nothing, "run_time"=>Nothing, "Profits"=>Profits, 
        "C_prices"=>C_price, "E_prices"=>E_price, "TEI"=>TEI, "x_new"=>x_new, "x_exist"=>x_exist)
end
