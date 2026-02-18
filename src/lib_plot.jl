#=
lib_plot:
- Julia version:
- Author: Nicolas
- Date: 2022-09-09
=#

#### SAVE SOLUTION
function save_model_solution(data, model, E_prices, profits, output_path, C_prices="none", solve_CRM_from_discrete=0)
    open(output_path*"profits.json","w") do f
        JSON.print(f, profits)
    end
    if C_prices != "none"
        C_price = Dict(i=>C_prices[i] for i in data["nodes"])
        open(output_path*"C_price.json","w") do f
            JSON.print(f, C_price)
        end
    end
    if solve_CRM_from_discrete != 1
        x_new = Dict(i=>Dict(g=>value(model[:x_new][i,g]) for g in data["generators_new"][i]) for i in data["generators_new_keys"])
        x_exist = Dict(i=>Dict(g=>value(model[:x_exist][i,g]) for g in data["generators_exist"][i]) for i in data["generators_exist_keys"])
        flow = Dict(i=>Dict(j=>Dict(t=>value(model[:flow][i,j,t]) for t in data["periods"]) for j in data["line_from"][i]) for i in data["line_from_keys"])
        load_shedding = Dict(i=>Dict(t=>value(model[:slack_pos][i,t]) for t in data["periods"]) for i in data["nodes"])
        supply_shedding = Dict(i=>Dict(t=>value(model[:slack_neg][i,t]) for t in data["periods"]) for i in data["nodes"])
        E_price = Dict(i=>Dict(t=>E_prices[i,t] for t in data["periods"]) for i in data["nodes"])
        p_new = Dict(i=>Dict(g=>Dict(t=>value(model[:p_new][i,g,t]) for t in data["periods"]) for g in data["generators_new"][i]) for i in data["generators_new_keys"])
        p_exist = Dict(i=>Dict(g=>Dict(t=>value(model[:p_exist][i,g,t]) for t in data["periods"]) for g in data["generators_exist"][i]) for i in data["generators_exist_keys"])

        open(output_path*"x_new.json","w") do f
            JSON.print(f, x_new)
        end
        open(output_path*"x_exist.json","w") do f
            JSON.print(f, x_exist)
        end
        open(output_path*"p_new.json","w") do f
            JSON.print(f, p_new)
        end
        open(output_path*"p_exist.json","w") do f
            JSON.print(f, p_exist)
        end
        open(output_path*"load_shedding.json","w") do f
            JSON.print(f, load_shedding)
        end
        open(output_path*"supply_shedding.json","w") do f
            JSON.print(f, supply_shedding)
        end
        open(output_path*"E_price.json","w") do f
            JSON.print(f, E_price)
        end
        open(output_path*"flow.json","w") do f
            JSON.print(f, flow)
        end
    end
end

##### INPUT plots
function plot_ICnew_per_techno(data, save_path="", save_fig=0)
    all_technos = unique([g for i in data["generators_new_keys"] for g in data["generators_new"][i]])
    IC_av_costs_per_techno = Dict(g=>mean([data["generators_data"]["New"][i][g]["IC"] for i in data["generators_new_keys"] if g in data["generators_new"][i]]) for g in all_technos)

    IC_min_costs_per_techno = Dict(g=>minimum([data["generators_data"]["New"][i][g]["IC"] for i in data["generators_new_keys"] if g in data["generators_new"][i]]) for g in all_technos)
    IC_max_costs_per_techno = Dict(g=>maximum([data["generators_data"]["New"][i][g]["IC"] for i in data["generators_new_keys"] if g in data["generators_new"][i]]) for g in all_technos)

    IC_av_cost_array = [IC_av_costs_per_techno[g] for g in all_technos]
    IC_min_costs_per_techno = [IC_min_costs_per_techno[g] for g in all_technos]
    IC_max_costs_per_techno = [IC_max_costs_per_techno[g] for g in all_technos]

    all_technos = all_technos[sortperm(IC_av_cost_array)]
    IC_min_costs_per_techno = IC_min_costs_per_techno[sortperm(IC_av_cost_array)]
    IC_max_costs_per_techno = IC_max_costs_per_techno[sortperm(IC_av_cost_array)]
    IC_av_cost_array_sorted = IC_av_cost_array[sortperm(IC_av_cost_array)]

    bar(all_technos, IC_max_costs_per_techno, legend = :topleft, labels="max",
        title="Average Investment Cost in New Technologies", ylabel = "[€/MWh]")
    bar!(all_technos, IC_av_cost_array_sorted, labels = "mean")
    bar!(all_technos, IC_min_costs_per_techno, labels = "min")

    if save_fig==1
        savefig("$save_path/ICnew_per_techno.pdf")
    end
end

function plot_ICexist_per_techno(data, save_path="", save_fig=0)
    all_technos = unique([g for i in data["generators_exist_keys"] for g in data["generators_exist"][i]])
    IC_av_costs_per_techno = Dict(g=>mean([data["generators_data"]["Exist"][i][g]["IC"] for i in data["generators_exist_keys"] if g in data["generators_exist"][i]]) for g in all_technos)

    IC_min_costs_per_techno = Dict(g=>minimum([data["generators_data"]["Exist"][i][g]["IC"] for i in data["generators_exist_keys"] if g in data["generators_exist"][i]]) for g in all_technos)
    IC_min_costs_per_techno = [IC_min_costs_per_techno[g] for g in all_technos]
    IC_max_costs_per_techno = Dict(g=>maximum([data["generators_data"]["Exist"][i][g]["IC"] for i in data["generators_exist_keys"] if g in data["generators_exist"][i]]) for g in all_technos)
    IC_max_costs_per_techno = [IC_max_costs_per_techno[g] for g in all_technos]

    IC_av_cost_array = [IC_av_costs_per_techno[g] for g in all_technos]
    all_technos = all_technos[sortperm(IC_av_cost_array)]
    IC_av_cost_array_sorted = IC_av_cost_array[sortperm(IC_av_cost_array)]
    IC_min_costs_per_techno = IC_min_costs_per_techno[sortperm(IC_av_cost_array)]
    IC_max_costs_per_techno = IC_max_costs_per_techno[sortperm(IC_av_cost_array)]

    plot(top_margin = 5Plots.mm, bottom_margin = 5Plots.mm, xtickfontsize=8, ytickfontsize=10, xguidefontsize=10, yguidefontsize=10,legendfontsize=10, titlefontsize=14)
    bar!(1:length(all_technos), IC_max_costs_per_techno, labels = "max")
    bar!(1:length(all_technos), IC_av_cost_array_sorted,xrotation=45, legend = :topleft, labels="mean",
        xticks=(1:length(all_technos), all_technos), title="Min/Mean/Max Retirement Fixed Cost Per Technology")
    bar!(1:length(all_technos), IC_min_costs_per_techno, labels = "min")

    if save_fig==1
        savefig("$save_path/ICexist_per_techno.pdf")
    end
end

function plot_OCnew_per_techno(data, save_path="", save_fig=0)
    all_technos = unique([g for i in data["generators_new_keys"] for g in data["generators_new"][i]])
    OC_av_costs_per_techno = Dict(g=>mean([data["generators_data"]["New"][i][g]["OC"] for i in data["generators_new_keys"] if g in data["generators_new"][i]]) for g in all_technos)

    OC_min_costs_per_techno = Dict(g=>minimum([data["generators_data"]["New"][i][g]["OC"] for i in data["generators_new_keys"] if g in data["generators_new"][i]]) for g in all_technos)
    OC_min_costs_per_techno = [OC_min_costs_per_techno[g] for g in all_technos]
    OC_max_costs_per_techno = Dict(g=>maximum([data["generators_data"]["New"][i][g]["OC"] for i in data["generators_new_keys"] if g in data["generators_new"][i]]) for g in all_technos)
    OC_max_costs_per_techno = [OC_max_costs_per_techno[g] for g in all_technos]

    OC_av_cost_array = [OC_av_costs_per_techno[g] for g in all_technos]
    all_technos = all_technos[sortperm(OC_av_cost_array)]
    OC_av_cost_array_sorted = OC_av_cost_array[sortperm(OC_av_cost_array)]

    OC_min_costs_per_techno = OC_min_costs_per_techno[sortperm(OC_av_cost_array)]
    OC_max_costs_per_techno = OC_max_costs_per_techno[sortperm(OC_av_cost_array)]

    str = [text("$(round(i,digits=1))",8) for i in OC_av_cost_array_sorted]
    y_pos = [i+0.05*maximum(OC_max_costs_per_techno) for i in OC_max_costs_per_techno]

    plot(top_margin = 5Plots.mm, bottom_margin = 5Plots.mm, xtickfontsize=8, ytickfontsize=10, xguidefontsize=10, yguidefontsize=10,legendfontsize=8, titlefontsize=12)
    bar!(1:length(all_technos), OC_max_costs_per_techno,xrotation=45,
        labels="max", xticks=(1:length(all_technos), all_technos))
    bar!(1:length(all_technos), OC_av_cost_array_sorted,xrotation=45,
        labels="mean", xticks=(1:length(all_technos), all_technos), title="Min/Mean/Max Operational Cost Per Existing Technology")
    bar!(1:length(all_technos), OC_min_costs_per_techno,xrotation=45,
        legend=:topleft, labels="min", xticks=(1:length(all_technos), all_technos))
    annotate!(1:length(all_technos),y_pos, str, :bottom)

    if save_fig==1
        savefig("$save_path/OCnew_per_techno.pdf")
    end
end


function plot_OCexist_per_techno(data, save_path="", save_fig=0)
    all_technos = unique([g for i in data["generators_exist_keys"] for g in data["generators_exist"][i]])
    OC_av_costs_per_techno = Dict(g=>mean([data["generators_data"]["Exist"][i][g]["OC"] for i in data["generators_exist_keys"] if g in data["generators_exist"][i]]) for g in all_technos)

    OC_min_costs_per_techno = Dict(g=>minimum([data["generators_data"]["Exist"][i][g]["OC"] for i in data["generators_exist_keys"] if g in data["generators_exist"][i]]) for g in all_technos)
    OC_min_costs_per_techno = [OC_min_costs_per_techno[g] for g in all_technos]
    OC_max_costs_per_techno = Dict(g=>maximum([data["generators_data"]["Exist"][i][g]["OC"] for i in data["generators_exist_keys"] if g in data["generators_exist"][i]]) for g in all_technos)
    OC_max_costs_per_techno = [OC_max_costs_per_techno[g] for g in all_technos]

    OC_av_cost_array = [OC_av_costs_per_techno[g] for g in all_technos]
    all_technos = all_technos[sortperm(OC_av_cost_array)]
    OC_av_cost_array_sorted = OC_av_cost_array[sortperm(OC_av_cost_array)]

    OC_min_costs_per_techno = OC_min_costs_per_techno[sortperm(OC_av_cost_array)]
    OC_max_costs_per_techno = OC_max_costs_per_techno[sortperm(OC_av_cost_array)]

    str = [text("$(round(i,digits=1))",8) for i in OC_av_cost_array_sorted]
    y_pos = [i+0.05*maximum(OC_max_costs_per_techno) for i in OC_max_costs_per_techno]

    plot(top_margin = 5Plots.mm, bottom_margin = 5Plots.mm, xtickfontsize=8, ytickfontsize=10, xguidefontsize=10, yguidefontsize=10,legendfontsize=8, titlefontsize=12)
    bar!(1:length(all_technos), OC_max_costs_per_techno,xrotation=45,
        labels="max", xticks=(1:length(all_technos), all_technos))
    bar!(1:length(all_technos), OC_av_cost_array_sorted,xrotation=45,
        labels="mean", xticks=(1:length(all_technos), all_technos), title="Min/Mean/Max Operational Cost Per Existing Technology")
    bar!(1:length(all_technos), OC_min_costs_per_techno,xrotation=45,
        legend=:topleft, labels="min", xticks=(1:length(all_technos), all_technos))
    annotate!(1:length(all_technos),y_pos, str, :bottom)

    if save_fig==1
        savefig("$save_path/OCexist_per_techno.pdf")
    end
end

function plot_load_boxplot(data, save_path="", save_fig=0)

    df = DataFrame(nodes = Any[], periods = Any[], load = Any[])
    for i in data["nodes"]
        for t in data["periods"]
            push!(df, [i  t data["load"][i][t]])
        end
    end

    @df df boxplot(:nodes, :load, size=(900,400), ylabel = "[MW]", left_margin = 5Plots.mm, legend=false,
        xrotation=45, xticks=(1:length(unique(df.nodes)), sort(unique(df.nodes))), title="Load Distribution Per Node")

    if save_fig == 1
        savefig("$save_path/load_boxplot.pdf")
    end
end

function plot_max_capa_new(data, save_path="", save_fig=0)
    constructable_capa = Dict(i=>Dict(g=>data["generators_data"]["New"][i][g]["CapaMax"] for g in data["generators_new"][i]) for i in data["generators_new_keys"])
    plot_two_indices_dict(constructable_capa, "Maximum Constructable New Capacity", "", "Max Constructable Capacity [MW]", save_path, "max_new_capa", save_fig)
end

function plot_max_capa_exist(data, save_path="", save_fig=0)
    retirable_capa = Dict(i=>Dict(g=>data["generators_data"]["Exist"][i][g]["RCapaMax"] for g in data["generators_exist"][i]) for i in data["generators_exist_keys"])

    #x_exist_nonzero = Dict(i=>Dict(g=>x_exist[i][g] for g in data["generators_exist"][i] if x_exist[i][g]>0) for i in data["generators_exist_keys"])
    #x_exist_nonzero2 = Dict(i=>Dict(g=>x_exist[i][g] for g in data["generators_exist"][i] if x_exist[i][g]>0) for i in data["generators_exist_keys"] if isempty(x_exist_nonzero[i])==false)

    ind_1 = [i for i in keys(retirable_capa)]
    ind_2 = unique([g for i in ind_1 for g in keys(retirable_capa[i])])
    processed_dict = [retirable_capa[i][g] for i in ind_1 for g in keys(retirable_capa[i])]
    ctg = [g for i in ind_1 for g in keys(retirable_capa[i])]
    nam = [i for i in ind_1 for g in keys(retirable_capa[i])]

    groupedbar(nam, processed_dict, group = ctg, size=(1000,400), xlabel = "", left_margin = 5Plots.mm,
    ylabel = "Max Retirable Capacity [MW]",title = "Maximum Retirable Capacity")
    if save_fig==1
        savefig("$save_path/max_retire_capa.pdf")
    end
end

################################################################################
##### OUTPUT plots
function plot_two_indices_dict(my_dict, title, xlabel, ylabel, save_path="", save_name="", save_fig=0)
    ind_1 = [i for i in keys(my_dict)]
    ind_2 = unique([g for i in ind_1 for g in keys(my_dict[i])])
    processed_dict = [my_dict[i][g] for g in ind_2 for i in ind_1]
    ctg = repeat(ind_2, inner = length(ind_1))
    nam = repeat(ind_1, outer = length(ind_2))

    groupedbar(nam, processed_dict, group = ctg, xlabel = xlabel, ylabel = ylabel,
        title = title, bar_width = 0.67,
        lw = 0, framestyle = :box, legend=:topleft, size=(1000,400),left_margin = 5Plots.mm)
    if save_fig==1
        savefig("$save_path/$save_name.pdf")
    end
end

function plot_x_new(x_new, data, title, xlabel, ylabel, save_path="", save_fig=0)
    x_new_nonzero = Dict(i=>Dict(g=>x_new[i,g] for g in data["generators_new"][i] if x_new[i,g]>0.1) for i in data["generators_new_keys"])
    x_new_nonzero2 = Dict(i=>Dict(g=>x_new[i,g] for g in data["generators_new"][i]) for i in data["generators_new_keys"] if isempty(x_new_nonzero[i])==false)
    plot_two_indices_dict(x_new_nonzero2, title, xlabel, ylabel, save_path, "x_new", save_fig)
end

function plot_x_new_discrete(x_new, data, title, xlabel, ylabel, save_path="", save_fig=0)
    x_new_nonzero = Dict(i=>Dict(g=>x_new[i,g]*data["generators_data"]["New"][i][g]["Lumps"] for g in data["generators_new"][i] if x_new[i,g]>0) for i in data["generators_new_keys"])
    x_new_nonzero2 = Dict(i=>Dict(g=>x_new[i,g]*data["generators_data"]["New"][i][g]["Lumps"] for g in data["generators_new"][i]) for i in data["generators_new_keys"] if isempty(x_new_nonzero[i])==false)
    if isempty(x_new_nonzero2)==false
        plot_two_indices_dict(x_new_nonzero2, title, xlabel, ylabel, save_path, "x_new", save_fig)
    end
end

function plot_x_exist(x_exist, data, title, xlabel, ylabel, save_path="", save_fig=0)
    x_exist_nonzero = Dict(i=>Dict(g=>x_exist[i,g] for g in data["generators_exist"][i] if x_exist[i,g]>0.1) for i in data["generators_exist_keys"])
    x_exist_nonzero2 = Dict(i=>Dict(g=>x_exist[i,g] for g in data["generators_exist"][i] if x_exist[i,g]>0.1) for i in data["generators_exist_keys"] if isempty(x_exist_nonzero[i])==false)

    ind_1 = [i for i in keys(x_exist_nonzero2)]
    ind_2 = unique([g for i in ind_1 for g in keys(x_exist_nonzero2[i])])
    processed_dict = [x_exist_nonzero2[i][g] for i in ind_1 for g in keys(x_exist_nonzero2[i])]
    ctg = [g for i in ind_1 for g in keys(x_exist_nonzero2[i])]
    nam = [i for i in ind_1 for g in keys(x_exist_nonzero2[i])]

    groupedbar(nam, processed_dict, group = ctg, size=(1000,400), xlabel = xlabel, ylabel = ylabel,
        title = title,left_margin = 5Plots.mm)
    if save_fig==1
        savefig("$save_path/x_exist.pdf")
    end
end

function plot_x_exist_discrete(x_exist, data, title, xlabel, ylabel, save_path="", save_fig=0)
    x_exist_nonzero = Dict(i=>Dict(g=>x_exist[i,g]*data["generators_data"]["Exist"][i][g]["Lumps"] for g in data["generators_exist"][i] if x_exist[i,g]>0) for i in data["generators_exist_keys"])
    x_exist_nonzero2 = Dict(i=>Dict(g=>x_exist[i,g]*data["generators_data"]["Exist"][i][g]["Lumps"] for g in data["generators_exist"][i] if x_exist[i,g]>0) for i in data["generators_exist_keys"] if isempty(x_exist_nonzero[i])==false)

    ind_1 = [i for i in keys(x_exist_nonzero2)]
    ind_2 = unique([g for i in ind_1 for g in keys(x_exist_nonzero2[i])])
    processed_dict = [x_exist_nonzero2[i][g] for i in ind_1 for g in keys(x_exist_nonzero2[i])]
    ctg = [g for i in ind_1 for g in keys(x_exist_nonzero2[i])]
    nam = [i for i in ind_1 for g in keys(x_exist_nonzero2[i])]

    groupedbar(nam, processed_dict, group = ctg, size=(1000,400), xlabel = xlabel, ylabel = ylabel,
        title = title,left_margin = 5Plots.mm)
    if save_fig==1
        savefig("$save_path/x_exist.pdf")
    end
end

function plot_load_shedding_num(supply_shedding, load_shedding, data, save_path="", save_fig=0)
    nodes = [i for i in data["nodes"] if sum(load_shedding[i,t] + supply_shedding[i,t] for t in data["periods"]) > 0.1]
    to_plot = Dict(i=>Dict("Load Shedding"=>length([load_shedding[i,t] for t in data["periods"] if load_shedding[i,t]>0.1]),
            "Prod Shedding"=>length([supply_shedding[i,t] for t in data["periods"] if supply_shedding[i,t]>0.1])) for i in nodes)
    plot_two_indices_dict(to_plot, "Occurrences of Load and Production Shedding", "", "Periods", save_path, "ls_ps_number", save_fig)
end

function plot_load_shedding_sum(supply_shedding, load_shedding, data, save_path="", save_fig=0)
    nodes = [i for i in data["nodes"] if sum(load_shedding[i,t] + supply_shedding[i,t] for t in data["periods"]) > 0.1]
    to_plot = Dict(i=>Dict("Load Shedding"=>sum(load_shedding[i,t] for t in data["periods"]),
            "Prod Shedding"=>sum(supply_shedding[i,t] for t in data["periods"])) for i in nodes)
    plot_two_indices_dict(to_plot, "Amount of Load and Production Shedding", "", "MWh", save_path, "ls_ps_sum", save_fig)
end

function plot_price_boxplot(price_dict, data, duration, save_path="", save_fig=0)
    # duration is needed because the price is the marginal cost of increasing the demand of 1 MW and if
    # it is for two hours, it means times 2
    df = DataFrame(nodes = Any[], periods = Any[], price = Any[])
    for i in data["nodes"]
        for t in data["periods"]
            push!(df, [i  t price_dict[i,t]/duration])
        end
    end

    @df df boxplot(:nodes, :price, size=(900,400), ylabel = "[€/MWh]", left_margin = 5Plots.mm, legend=false,
        xrotation=45, xticks=(1:length(unique(df.nodes)), sort(unique(df.nodes))), ylim=(0,100), title="Price Distribution Per Node")

    if save_fig == 1
        savefig("$save_path/price_boxplot.pdf")
    end
end

function plot_netposition_boxplot(flow, data, save_path="", save_fig=0)
    # 1 transform to net position
    net_position = Dict(i =>
        Dict(t => ((i in data["line_from_keys"] ? sum(flow[i,j,t] for j in data["line_from"][i]) : 0.0)
                - (i in data["line_to_keys"] ? sum(flow[j,i,t] for j in data["line_to"][i]) : 0.0))
            for t in data["periods"])
        for i in data["nodes"])

    df = DataFrame(nodes = Any[], periods = Any[], netposition = Any[])
    for i in data["nodes"]
        for t in data["periods"]
            push!(df, [i  t net_position[i][t]])
        end
    end

    @df df boxplot(:nodes, :netposition, size=(900,400), ylabel = "[MW]", left_margin = 5Plots.mm, legend=false,
        xrotation=45, xticks=(1:length(unique(df.nodes)), sort(unique(df.nodes))), title="Net Position Distribution For Each Node")

    if save_fig == 1
        savefig("$save_path/netposition_boxplot.pdf")
    end
end

function plot_loc(profits, gen_type, save_path="", save_fig=0)
    index_profits1 = [i for i in keys(profits)][1]
    loc_gens = Dict("$i - $g"=>Dict(l=>profits[l][gen_type][i][g] for l in keys(profits)) for i in keys(profits[index_profits1][gen_type]) for g in keys(profits[index_profits1][gen_type][i]))

    ind_1 = [i for i in keys(loc_gens)]
    ind_2 = unique([g for i in ind_1 for g in keys(loc_gens[i])])
    processed_dict = [loc_gens[i][g] for i in ind_1 for g in keys(loc_gens[i])]
    ctg = [g for i in ind_1 for g in keys(loc_gens[i])]
    nam = [i for i in ind_1 for g in keys(loc_gens[i])]

    groupedbar(nam, processed_dict, group = ctg, size=(1000,500), xlabel = "", ylabel = "[€]",xrotation=45,
        left_margin = 5Plots.mm, bottom_margin = 8Plots.mm, title = "Profits and Lost Opportunity Costs of the $gen_type units")
    if save_fig==1
        savefig("$save_path/profits_and_LOC_$gen_type.pdf")
    end
end

function plot_Cprice(C_price, save_path="", save_fig=0)
    keys_C_price = [i for i in keys(C_price)]
    plot(top_margin = 5Plots.mm, bottom_margin = 5Plots.mm, left_margin = 5Plots.mm, xtickfontsize=8, ytickfontsize=10, xguidefontsize=10,
        yguidefontsize=10,legendfontsize=10, titlefontsize=14)
    bar!(keys_C_price, [C_price[i] for i in keys(C_price)], xrotation=45, legend = false,
        xticks=(1:length(keys_C_price), keys_C_price), title="Capacity prices", ylabel = "€/MW", size=(1000,500))
    if save_fig==1
        savefig("$save_path/Cprice.pdf")
    end
end

function writeRunSummary(model, x_new, data, profits, total_costs, run_time, TEI, discrete, 
    save_path="", save_fig=0, solve_CRM_from_discrete=0)
    # save: run time, objective, total LOC New, total LOC exist
    # total IC and OC costs
    summary_tab = Dict()
    if solve_CRM_from_discrete!=1
        summary_tab["CPU time"] = run_time
        summary_tab["Objective Value"] = objective_value(model)
        summary_tab["Total Fixed Costs"] = total_costs["Investment cost"]
        summary_tab["Total Operational Costs"] = total_costs["Operational Cost"]
    end
    
    summary_tab["TEI"] = TEI
    summary_tab["Total LOC New"] = sum(profits["LOC"]["New"][i][g] for i in keys(profits["LOC"]["New"]) for g in keys(profits["LOC"]["New"][i]))
    summary_tab["Total LOC Exist"] = sum(profits["LOC"]["Exist"][i][g] for i in keys(profits["LOC"]["Exist"]) for g in keys(profits["LOC"]["Exist"][i]))

    gen_type = "New"
    res = comp_total_loc_mwp(profits, gen_type)
    summary_tab["$gen_type Revenue Shortfall"] = res["Revenue Shortfall"]
    summary_tab["$gen_type Revenue Shortfall (in LOC)"] = res["Revenue Shortfall (in LOC)"]
    summary_tab["$gen_type Revenue Shortfall (NOT in LOC)"] = res["Revenue Shortfall (NOT in LOC)"]
    summary_tab["$gen_type Foregone Opportunity"] = res["Foregone Opportunity"]
    gen_type = "Exist"
    res = comp_total_loc_mwp(profits, gen_type)
    summary_tab["$gen_type Revenue Shortfall"] = res["Revenue Shortfall"]
    summary_tab["$gen_type Revenue Shortfall (in LOC)"] = res["Revenue Shortfall (in LOC)"]
    summary_tab["$gen_type Revenue Shortfall (NOT in LOC)"] = res["Revenue Shortfall (NOT in LOC)"]
    summary_tab["$gen_type Foregone Opportunity"] = res["Foregone Opportunity"]

    # commisioning and Decommissioning 
    if discrete==0
        summary_tab["Total Commissioning"] = round(sum(value(model[:x_new][i,g]) for i in data["generators_new_keys"] for g in data["generators_new"][i]))
        summary_tab["Total Decommissioning"] = round(sum(value(model[:x_exist][i,g]) for i in data["generators_exist_keys"] for g in data["generators_exist"][i]))
    else
        if solve_CRM_from_discrete != 1
            summary_tab["MIP gap"] = relative_gap(model)
            summary_tab["Total Commissioning"] = round(sum(data["generators_data"]["New"][i][g]["Lumps"] * value(model[:x_new][i,g]) for i in data["generators_new_keys"] for g in data["generators_new"][i]))
            summary_tab["Total Decommissioning"] = round(sum(data["generators_data"]["Exist"][i][g]["Lumps"] * value(model[:x_exist][i,g]) for i in data["generators_exist_keys"] for g in data["generators_exist"][i]))
        end
    end

    if discrete==1 # only execute this part when discrete investment model is solved
        res_discreteness_rent =  comp_discreteness_rent(data, profits, x_new)
        inter = Dict(i => res_discreteness_rent["discretness_rent"][i] for i in keys(res_discreteness_rent["discretness_rent"]) if res_discreteness_rent["discretness_rent"][i] > 0.0)
        mean_inter = mean(Float64[inter[i] for i in keys(inter)])
        summary_tab["Installed New Gen with Foregone Opp"] = res_discreteness_rent["count_constructed"]
        summary_tab["NOT Installed New Gen with Foregone Opp"] = res_discreteness_rent["count_not_constructed"]
        summary_tab["Av. discreteness rent for New installed gen"] = mean_inter
    end

    if save_fig==1
        CSV.write("$save_path/summary_table.csv", summary_tab)
    end
    return summary_tab
end


function comp_total_loc_mwp(profits, gen_type)
    revenue_shortfall = Dict((i,g)=>max(-profits["As-Cleared Profit"][gen_type][i][g],0.0) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))
    revenue_shortfall_notinLOC = Dict((i,g)=>max(revenue_shortfall[(i,g)] - profits["LOC"][gen_type][i][g],0.0) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))
    revenue_shortfall_inLOC = Dict((i,g)=>(revenue_shortfall[(i,g)]-revenue_shortfall_notinLOC[(i,g)]) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))
    foregone_opportunity = Dict((i,g)=>(profits["LOC"][gen_type][i][g]-revenue_shortfall_inLOC[(i,g)]) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))

    tot_revenue_shortfall = sum([revenue_shortfall[(i,g)] for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i])])
    revenue_shortfall_notinLOC = sum([revenue_shortfall_notinLOC[(i,g)] for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i])])
    revenue_shortfall_inLOC = sum([revenue_shortfall_inLOC[(i,g)] for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i])])
    foregone_opportunity = sum([foregone_opportunity[(i,g)] for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i])])

    return Dict("Revenue Shortfall"=>tot_revenue_shortfall, "Revenue Shortfall (in LOC)"=>revenue_shortfall_inLOC,
    "Revenue Shortfall (NOT in LOC)"=>revenue_shortfall_notinLOC, "Foregone Opportunity"=>foregone_opportunity)
end

"""
The function computes the rent in €/MW/year that a New unit facing a foregone
    opportunity is earning.
"""
function comp_discreteness_rent(data, profits, x_new)
    revenue_shortfall = Dict((i,g)=>max(-profits["As-Cleared Profit"]["New"][i][g],0.0) for i in keys(profits["As-Cleared Profit"]["New"]) for g in keys(profits["As-Cleared Profit"]["New"][i]))
    revenue_shortfall_notinLOC = Dict((i,g)=>max(revenue_shortfall[(i,g)] - profits["LOC"]["New"][i][g],0.0) for i in keys(profits["As-Cleared Profit"]["New"]) for g in keys(profits["As-Cleared Profit"]["New"][i]))
    revenue_shortfall_inLOC = Dict((i,g)=>(revenue_shortfall[(i,g)]-revenue_shortfall_notinLOC[(i,g)]) for i in keys(profits["As-Cleared Profit"]["New"]) for g in keys(profits["As-Cleared Profit"]["New"][i]))
    foregone_opportunity = Dict((i,g)=>(profits["LOC"]["New"][i][g]-revenue_shortfall_inLOC[(i,g)]) for i in keys(profits["As-Cleared Profit"]["New"]) for g in keys(profits["As-Cleared Profit"]["New"][i]))

    # for those with positive foregone_opportunity, compute the
    discretness_rent = Dict((i,g)=>0.0 for i in keys(profits["As-Cleared Profit"]["New"]) for g in keys(profits["As-Cleared Profit"]["New"][i]))
    count_not_constructed = 0.0
    count_constructed = 0.0
    for i in keys(profits["As-Cleared Profit"]["New"])
        for g in keys(profits["As-Cleared Profit"]["New"][i])
            if foregone_opportunity[(i,g)]>0.1
                if x_new[i,g]>0
                    count_constructed = count_constructed + 1
                    discretness_rent[(i,g)] = profits["As-Cleared Profit"]["New"][i][g]/(x_new[i,g]*data["generators_data"]["New"][i][g]["Lumps"])
                else
                    count_not_constructed = count_not_constructed + 1
                end
            end
        end
    end

    return Dict("count_not_constructed"=>count_not_constructed, "count_constructed"=>count_constructed,
    "discretness_rent"=>discretness_rent)
end

"""
The function compute the % of time for which a technology (New or Exist) is running in each node
"""
function compute_percent_active(data, p_new, p_exist, x_new, x_exist)
    active_prod = Dict((i,g)=>length([p_exist[i,g,t] for t in data["periods"] if p_exist[i,g,t]>0.1])/length(data["periods"])
            for i in data["generators_exist_keys"] for g in data["generators_exist"][i]
                if (data["generators_data"]["Exist"][i][g]["Max Rating"] - x_exist[i, g] * data["generators_data"]["Exist"][i][g]["Lumps"] > 0)) # we only want to include the places where there is capacity
    for i in data["generators_new_keys"]
        for g in data["generators_new"][i]
            if x_new[i,g]>0 # we only want to include the places where there is capacity
                active_prod[(i,g)] = length([p_new[i,g,t] for t in data["periods"] if p_new[i,g,t]>0.1])/length(data["periods"])
            end
        end
    end
    return active_prod
end

"""
The function compute the % of time for which a technology (New or Exist) sets the price
"""
function compute_percent_setprice(data, p_new, p_exist, x_new, x_exist, price)
    set_price = Dict((i,g)=>length([p_exist[i,g,t] for t in data["periods"]
                    if (p_exist[i,g,t]>0.01 && abs(data["generators_data"]["Exist"][i][g]["OC"]*data["deltaT"]-price[i,t])<0.3)])/length(data["periods"])
            for i in data["generators_exist_keys"] for g in data["generators_exist"][i]
                if (data["generators_data"]["Exist"][i][g]["Max Rating"] - x_exist[i, g] * data["generators_data"]["Exist"][i][g]["Lumps"] > 0)) # we only want to include the places where there is capacity)
    for i in data["generators_new_keys"]
        for g in data["generators_new"][i]
            if x_new[i,g]>0 # we only want to include the places where there is capacity
                set_price[(i,g)] = length([p_new[i,g,t] for t in data["periods"]
                            if (p_new[i,g,t]>0.01 && abs(data["generators_data"]["New"][i][g]["OC"]*data["deltaT"]-price[i,t])<0.3)])/length(data["periods"])
            end
        end
    end
    return set_price
end

function plot_active_prod_boxplot(active_prod, title, save_path="", save_name="", save_fig=0)
    df = DataFrame(Technology = Any[], Node = Any[], Active_prod = Any[])
    for (i,g) in keys(active_prod)
        push!(df, [g  i active_prod[(i,g)]])
    end

    @df df boxplot(:Technology, :Active_prod, size=(900,400), ylabel = "", left_margin = 5Plots.mm,
    legend=false, ylim=(0,1), bottom_margin = 8Plots.mm, xrotation=45,
    xticks=(1:length(unique(df.Technology)), sort(unique(df.Technology))),title=title)

    if save_fig == 1
        savefig("$save_path/$save_name.pdf")
    end
end

"""
Function that writes the investment/profits/LOC per power plant (for the New
power plants) in a latex formated table.
inputs are:
    - data: the dict containing the input data
    - profits: the dict containing the as-cleared profit and LOC of agents
    - x_new: the opt investment decisions for new power plants
    - file_path: the name of the file
    - discrete: 1 if it is a discrete investment model (x_new is Int), 0 otherwise
"""
function write_latextable_profitNew(data, profits, x_new, file_path, discrete)
    gen_type = "New"
    revenue_shortfall = Dict((i,g)=>max(-profits["As-Cleared Profit"][gen_type][i][g],0.0) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))
    revenue_shortfall_notinLOC = Dict((i,g)=>max(revenue_shortfall[(i,g)] - profits["LOC"][gen_type][i][g],0.0) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))
    revenue_shortfall_inLOC = Dict((i,g)=>(revenue_shortfall[(i,g)]-revenue_shortfall_notinLOC[(i,g)]) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))
    foregone_opportunity = Dict((i,g)=>(profits["LOC"][gen_type][i][g]-revenue_shortfall_inLOC[(i,g)]) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))

    open(file_path, "w") do f
        println(f, "Zone & Technology & Investment & Profit & LOC & Rev. Shortfall & Foregone Opp. \\\\")
        println(f, "\\hline")
        for i in keys(profits["As-Cleared Profit"][gen_type])
            for g in keys(profits["As-Cleared Profit"][gen_type][i])
                # only write the non-zero lines
                if (x_new[i,g] + abs(profits["As-Cleared Profit"][gen_type][i][g] + profits["LOC"][gen_type][i][g])) > 0.1
                    if discrete==1
                        println(f, "$i & $g & $(Int(round(x_new[i,g]))) \$\\times\$ $(data["generators_data"][gen_type][i][g]["Lumps"])  & $(round(round(profits["As-Cleared Profit"][gen_type][i][g]),sigdigits=4)) & $(round(round(profits["LOC"][gen_type][i][g]),sigdigits=4)) & $(round(round(revenue_shortfall_inLOC[i,g]),sigdigits=4)) & $(round(round(foregone_opportunity[i,g]),sigdigits=4)) \\\\")
                    else
                        println(f, "$i & $g & $(round(x_new[i,g])) & $(round(round(profits["As-Cleared Profit"][gen_type][i][g]),sigdigits=4)) & $(round(round(profits["LOC"][gen_type][i][g]),sigdigits=4)) & $(round(round(revenue_shortfall_inLOC[i,g]),sigdigits=4)) & $(round(round(foregone_opportunity[i,g]),sigdigits=4)) \\\\")
                    end
                end
            end
            flush(f)
        end
        println(f, "\\hline")
    end
end

"""
Function that writes the investment/profits/LOC per power plant (for the Exist
power plants) in a latex formated table.
inputs are:
    - data: the dict containing the input data
    - profits: the dict containing the as-cleared profit and LOC of agents
    - x_exist: the opt investment (decomissionning) decisions for exist power plants
    - file_path: the name of the file
    - discrete: 1 if it is a discrete investment model (x_new is Int), 0 otherwise
"""
function write_latextable_profitExist(data, profits, x_exist, file_path, discrete)
    gen_type = "Exist"
    revenue_shortfall = Dict((i,g)=>max(-profits["As-Cleared Profit"][gen_type][i][g],0.0) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))
    revenue_shortfall_notinLOC = Dict((i,g)=>max(revenue_shortfall[(i,g)] - profits["LOC"][gen_type][i][g],0.0) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))
    revenue_shortfall_inLOC = Dict((i,g)=>(revenue_shortfall[(i,g)]-revenue_shortfall_notinLOC[(i,g)]) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))
    foregone_opportunity = Dict((i,g)=>(profits["LOC"][gen_type][i][g]-revenue_shortfall_inLOC[(i,g)]) for i in keys(profits["As-Cleared Profit"][gen_type]) for g in keys(profits["As-Cleared Profit"][gen_type][i]))

    open(file_path, "w") do f
        println(f, "Zone & Technology & In Place & Decommission. & Profit & LOC & Rev. Shortfall & Foregone Opp. \\\\")
        println(f, "\\hline")
        for i in keys(profits["As-Cleared Profit"][gen_type])
            for g in keys(profits["As-Cleared Profit"][gen_type][i])
                # only write the non-zero lines
                if (x_exist[i,g] + abs(profits["LOC"][gen_type][i][g])) > 0.1
                    if discrete==1
                        println(f, "$i & $g & $(round(data["generators_data"][gen_type][i][g]["Max Rating"]))  & $(Int(x_exist[i,g])) \$\\times\$ $(data["generators_data"][gen_type][i][g]["Lumps"])  & $(round(round(profits["As-Cleared Profit"][gen_type][i][g]),sigdigits=4)) & $(round(round(profits["LOC"][gen_type][i][g]),sigdigits=4)) & $(round(round(revenue_shortfall_inLOC[i,g]),sigdigits=4)) & $(round(round(foregone_opportunity[i,g]),sigdigits=4)) \\\\")
                    else
                        println(f, "$i & $g & $(round(data["generators_data"][gen_type][i][g]["Max Rating"]))  & $(round(x_exist[i,g])) & $(round(round(profits["As-Cleared Profit"][gen_type][i][g]),sigdigits=4)) & $(round(round(profits["LOC"][gen_type][i][g]),sigdigits=4)) & $(round(round(revenue_shortfall_inLOC[i,g]),sigdigits=4)) & $(round(round(foregone_opportunity[i,g]),sigdigits=4)) \\\\")
                    end
                end
            end
            flush(f)
        end
        println(f, "\\hline")
    end
end
