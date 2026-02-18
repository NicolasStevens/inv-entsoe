# The functions for loading and processing the data

function load_data(data_path, year, CO2_price, VOLL)
    println("Loading the raw data...")
    battery = JSON.parsefile(data_path*"battery.json")
    Fuels = JSON.parsefile(data_path*"Fuels.json");
    other_res_nores = JSON.parsefile(data_path*"other_res_nores.json");
    Generator_Data = JSON.parsefile(data_path*"Generator_Data.json");
    Generators = Generator_Data["Generators"]
    Generator_Data = nothing

    Lines_Data = JSON.parsefile(data_path*"Lines_Data.json");
    LinesFrom = Lines_Data["LinesFrom"]
    LinesTo = Lines_Data["LinesTo"]
    Lines = Lines_Data["Lines"]
    Lines_Data = nothing

    Hydro_Data = JSON.parsefile(data_path*"Hydro_Data.json")

    Loads_Data = JSON.parsefile(data_path*"Loads_Data.json");
    ParsedLoad = Loads_Data["ParsedLoad"]
    DSR = Loads_Data["DSR"]
    Loads_Data = nothing

    println("data loaded.")
    println("Processing the raw data...")
    final_data = process_data(Generators, battery, Fuels, other_res_nores, ParsedLoad, Hydro_Data, LinesFrom, LinesTo,
        Lines, DSR, year, CO2_price, VOLL)
    println("data processed.")
    return final_data
end


function process_data(Generators, battery, Fuels, other_res_nores, ParsedLoad, Hydro_Data, LinesFrom, LinesTo,
        Lines, DSR, year, CO2_price, VOLL)
    # The function process the raw data by selecting a specific year and creating additonal set and fields
    # as well as processing the existing fields, in other to simplify the model
    # create deltaT: the length of each period. It is 2 hours
    deltaT = 2
    # create node set
    Nodes = [i for i in keys(Generators["Exist"])]
    # load processing:
    # select year 2016, transform to hourly resolution and construct the "net load":
    # ParsedLoad - other_res_nores[code]["Others renewable"]["Max Capacity"] - ["Others non-renewable"]["Max Capacity"]
    # also net it with Hydro["Run-of-River"]
    load_year = year - 1982 + 1 # this is the year number (e.g. 2016 = load year 35)
    Load = Dict(i=>(ParsedLoad[i][load_year] .- (other_res_nores[i]["Others renewable"]["Max Capacity"]
            + other_res_nores[i]["Others non-renewable"]["Max Capacity"])) for i in Nodes)
    hydro_year = "$year Climate"
    for i in Nodes
        if "Run-of-River" in keys(Hydro_Data["hydro"][i])
            Load[i] = Load[i] - Hydro_Data["hydro_storage"][i]["Run-of-River"]["Head Storage"]["Natural Inflow"][hydro_year]
        end
    end
    # create time set
    periods = [i for i in 1:length(Load["BE00"])]

    # create useful sets (generators in each node, DSR, battery, hydro)
    generators_new = Dict(i=>[j for j in keys(Generators["New"][i])] for i in Nodes)
    generators_new_keys = [i for i in keys(generators_new) if length(generators_new[i])>0]
    generators_exist = Dict(i=>[j for j in keys(Generators["Exist"][i])] for i in Nodes)
    generators_exist_keys = [i for i in keys(generators_exist) if length(generators_exist[i])>0]
    dsr = Dict(i=>[j for j in keys(DSR[i])] for i in Nodes)
    dsr_keys = [i for i in keys(dsr) if length(dsr[i])>0]
    node_battery = [i for i in Nodes if "Battery" in keys(battery[i])]
    hydro_types = ["Reservoir", "PS Open", "PS Closed"]
    node_hydro = Dict("Reservoir"=>[i for i in Nodes if "Reservoir" in keys(Hydro_Data["hydro"][i])],
        "PS Open"=>[i for i in Nodes if "PS Open" in keys(Hydro_Data["hydro"][i])],
        "PS Closed"=>[i for i in Nodes if "PS Closed" in keys(Hydro_Data["hydro"][i])])

    ### Generator data
    # Create fiels Operational cost ("OC"), Investment cost ("IC") and CapaMax, RCapaMax and CapaMin for the generators
    for i in keys(generators_new)
        for j in generators_new[i]
            Generators["New"][i][j]["IC"] = Generators["New"][i][j]["Annualized Build Cost"] + 1000*Generators["New"][i][j]["FO&M Charge"]
            Generators["New"][i][j]["OC"] = Generators["New"][i][j]["VO&M Charge"] + Generators["New"][i][j]["Heat Rate"] * Fuels[Generators["New"][i][j]["Fuel Type"]]["Price"] + CO2_price * Generators["New"][i][j]["Heat Rate"] * Fuels[Generators["New"][i][j]["Fuel Type"]]["Production Rate"]
            Generators["New"][i][j]["CapaMax"] = Generators["New"][i][j]["Max Capacity"] * Generators["New"][i][j]["Max Units Built"]
        end
    end

    for i in keys(generators_exist)
        for j in generators_exist[i]
            Generators["Exist"][i][j]["IC"] = 1000 * Generators["Exist"][i][j]["FO&M Charge"]
            Generators["Exist"][i][j]["OC"] = Generators["Exist"][i][j]["VO&M Charge"] + Generators["Exist"][i][j]["Heat Rate"] * Fuels[Generators["Exist"][i][j]["Fuel Type"]]["Price"] + CO2_price * Generators["Exist"][i][j]["Heat Rate"] * Fuels[Generators["Exist"][i][j]["Fuel Type"]]["Production Rate"]
            Generators["Exist"][i][j]["RCapaMax"] = Generators["Exist"][i][j]["Retire capacity"] * Generators["Exist"][i][j]["Max Units Retired"]
            Generators["Exist"][i][j]["Max Rating"] = maximum(Generators["Exist"][i][j]["Rating"])
        end
    end

    ### Line data
    # aggregate lines together (aggregate "sub-line" 1, 2... and also HVDC and HVAC since they are all ATC...)
    # set that aggregate HVDC and HVAC
    line_from = Dict(i => unique(vcat([j for j in keys(LinesFrom["HVAC"][i])],[j for j in keys(LinesFrom["HVDC"][i])])) for i in keys(LinesFrom["HVAC"]))
    line_to = Dict(i => unique(vcat([j for j in keys(LinesTo["HVAC"][i])],[j for j in keys(LinesTo["HVDC"][i])])) for i in keys(LinesTo["HVAC"]))
    line_from_keys = [i for i in keys(line_from) if length(line_from[i])>0] # the keys that are non-empty
    line_to_keys = [i for i in keys(line_to) if length(line_to[i])>0] # the keys that are non-empty
    # data that aggregate all HVDC and HVAC lines
    # initialize data structure
    line_data = Dict(i => Dict(j => Dict("Min Flow" => [0.0 for t in periods],
                "Wheeling Charge" => 0.0,
                "Max Flow" => [0.0 for t in periods])
            for j in line_from[i]) for i in keys(line_from))
    # fill HVAC lines data
    for i in keys(LinesFrom["HVAC"])
        for j in keys(LinesFrom["HVAC"][i])
            line_data[i][j]["Min Flow"] = line_data[i][j]["Min Flow"] + sum(Lines["HVAC"][i][j][k]["Min Flow"] for k in keys(Lines["HVAC"][i][j]))
            line_data[i][j]["Wheeling Charge"] = abs(round(mean([Lines["HVAC"][i][j][k]["Wheeling Charge"] for k in keys(Lines["HVAC"][i][j])]),digits=3))
            line_data[i][j]["Max Flow"] = line_data[i][j]["Max Flow"] + sum(Lines["HVAC"][i][j][k]["Max Flow"] for k in keys(Lines["HVAC"][i][j]))
        end
    end

    # fill HVDC lines data
    for i in keys(LinesFrom["HVDC"])
        for j in keys(LinesFrom["HVDC"][i])
            line_data[i][j]["Min Flow"] = line_data[i][j]["Min Flow"] + sum(Lines["HVDC"][i][j][k]["Min Flow"] for k in keys(Lines["HVDC"][i][j]))
            line_data[i][j]["Wheeling Charge"] = abs(round(mean([Lines["HVDC"][i][j][k]["Wheeling Charge"] for k in keys(Lines["HVDC"][i][j])]),digits=3))
            line_data[i][j]["Max Flow"] = line_data[i][j]["Max Flow"] + sum(Lines["HVDC"][i][j][k]["Max Flow"] for k in keys(Lines["HVDC"][i][j]))
        end
    end

    ### Battery data: reduce dict and change battery Charge Efficiency to %?
    battery_data = Dict(i=>battery[i]["Battery"] for i in node_battery)
    for i in node_battery
        battery_data[i]["Charge Efficiency"] = battery_data[i]["Charge Efficiency"]/100
        battery_data[i]["Init Volume"] = battery_data[i]["Capacity"] * battery_data[i]["Initial SoC"]/100
    end

    ### Hydro data
    # 1-change to all hydro
    # change "Spill Penalty" = "Spill Penalty"/1000 and Max Volume = Max Volume * 1000
    # keep only the right year for initial volume and Natural Inflow
    # Initial head volume is * 1000
    # Create Rating for turb when does not exist (set to Max Capacity)
    # Turn Rating to time series when it is a scalar
    for h in hydro_types
        for i in node_hydro[h]
            Hydro_Data["hydro_storage"][i][h]["Head Storage"]["Spill Penalty"] = Hydro_Data["hydro_storage"][i][h]["Head Storage"]["Spill Penalty"]/1000
            Hydro_Data["hydro_storage"][i][h]["Head Storage"]["Max Volume"] = Hydro_Data["hydro_storage"][i][h]["Head Storage"]["Max Volume"]*1000
            if isa(Hydro_Data["hydro_storage"][i][h]["Head Storage"]["Initial Volume"], Dict)
                Hydro_Data["hydro_storage"][i][h]["Head Storage"]["Initial Volume"] = Hydro_Data["hydro_storage"][i][h]["Head Storage"]["Initial Volume"][hydro_year]
            end
            Hydro_Data["hydro_storage"][i][h]["Head Storage"]["Initial Volume"] = Hydro_Data["hydro_storage"][i][h]["Head Storage"]["Initial Volume"]*1000
            # if field rating does not exist create it
            if ("Rating" in keys(Hydro_Data["hydro"][i][h])) == false
                Hydro_Data["hydro"][i][h]["Rating"] = Hydro_Data["hydro"][i][h]["Max Capacity"]
            end
            # some Rating are Dict with "xxx Climate" keys --> choose the right one
            if isa(Hydro_Data["hydro"][i][h]["Rating"], Dict) == true
                Hydro_Data["hydro"][i][h]["Rating"] = Hydro_Data["hydro"][i][h]["Rating"][hydro_year]
            end
            if isa(Hydro_Data["hydro"][i][h]["Rating"], Array) == false
                Hydro_Data["hydro"][i][h]["Rating"] = [Hydro_Data["hydro"][i][h]["Rating"] for t in periods]
            end
        end
    end
    # 2- change to PS hydro
    # change Hydro efficiency to %
    # Initial tail volume * 1000
    # Make "Pump Load" an array when it is a scalar
    for h in ["PS Open", "PS Closed"]
        for i in node_hydro[h]
            Hydro_Data["hydro"][i][h]["Pump Efficiency"] = Hydro_Data["hydro"][i][h]["Pump Efficiency"]/100
            if isa(Hydro_Data["hydro_storage"][i][h]["Tail Storage"]["Initial Volume"], Dict)
                Hydro_Data["hydro_storage"][i][h]["Tail Storage"]["Initial Volume"] = Hydro_Data["hydro_storage"][i][h]["Tail Storage"]["Initial Volume"][hydro_year]
            end
            Hydro_Data["hydro_storage"][i][h]["Tail Storage"]["Initial Volume"] = Hydro_Data["hydro_storage"][i][h]["Tail Storage"]["Initial Volume"]*1000
            if isa(Hydro_Data["hydro"][i][h]["Pump Load"], Dict) == true
                Hydro_Data["hydro"][i][h]["Pump Load"] = Hydro_Data["hydro"][i][h]["Pump Load"][hydro_year]
            end
            if isa(Hydro_Data["hydro"][i][h]["Pump Load"], Array) == false
                Hydro_Data["hydro"][i][h]["Pump Load"] = [Hydro_Data["hydro"][i][h]["Pump Load"] for t in periods]
            end
        end
    end
    # 3- change to Reservoir and PS Open (inflows)
    # keep only the right year for Natural Inflow
    for h in ["Reservoir", "PS Open"]
        for i in node_hydro[h]
            Hydro_Data["hydro_storage"][i][h]["Head Storage"]["Natural Inflow"] = Hydro_Data["hydro_storage"][i][h]["Head Storage"]["Natural Inflow"][hydro_year]
        end
    end

    processed_data = Dict("VOLL"=>VOLL, "nodes"=>Nodes, "periods"=>periods, "generators_new"=>generators_new,
        "generators_exist"=>generators_exist, "dsr"=>dsr, "dsr_keys"=>dsr_keys, "node_battery"=>node_battery, "node_hydro"=>node_hydro,
        "generators_data"=>Generators, "line_from_keys"=>line_from_keys, "line_from"=>line_from, "line_to"=>line_to,
        "line_data"=>line_data, "dsr_data"=>DSR, "battery_data"=>battery_data, "load"=>Load, "hydro_data"=>Hydro_Data,
        "hydro_types"=>hydro_types, "generators_new_keys"=>generators_new_keys, "generators_exist_keys"=>generators_exist_keys,
        "line_to_keys"=>line_to_keys, "deltaT"=>deltaT
    )
    return processed_data
end

function keep_subset_nodes(data, selected_nodes)
    data["generators_new_keys"] = [i for i in data["generators_new_keys"] if i in selected_nodes]
    data["generators_exist_keys"] = [i for i in data["generators_exist_keys"] if i in selected_nodes]
    data["node_hydro"]["PS Closed"] = [i for i in data["node_hydro"]["PS Closed"] if i in selected_nodes]
    data["node_hydro"]["PS Open"] = [i for i in data["node_hydro"]["PS Open"] if i in selected_nodes]
    data["node_hydro"]["Reservoir"] = [i for i in data["node_hydro"]["Reservoir"] if i in selected_nodes]
    data["dsr_keys"] = [i for i in data["dsr_keys"] if i in selected_nodes]
    data["node_battery"] = [i for i in data["node_battery"] if i in selected_nodes]
    data["nodes"] = [i for i in data["nodes"] if i in selected_nodes]

    data["generators_exist"] = Dict(i => data["generators_exist"][i] for i in data["generators_exist_keys"])
    data["dsr_data"] = Dict(i => data["dsr_data"][i] for i in keys(data["dsr_data"]) if i in selected_nodes)
    data["dsr"] = Dict(i => data["dsr"][i] for i in keys(data["dsr"]) if i in selected_nodes)
    data["battery_data"] = Dict(i => data["battery_data"][i] for i in keys(data["battery_data"]) if i in selected_nodes)
    data["load"] = Dict(i => data["load"][i] for i in keys(data["load"]) if i in selected_nodes)
    data["generators_new"] = Dict(i => data["generators_new"][i] for i in data["generators_new_keys"])
    data["generators_data"]["New"] = Dict(i => data["generators_data"]["New"][i] for i in keys(data["generators_data"]["New"]) if i in selected_nodes)
    data["generators_data"]["Exist"] = Dict(i => data["generators_data"]["Exist"][i] for i in keys(data["generators_data"]["Exist"]) if i in selected_nodes)
    data["hydro_data"]["hydro_storage"] = Dict(i => data["hydro_data"]["hydro_storage"][i] for i in keys(data["hydro_data"]["hydro_storage"]) if i in selected_nodes)
    data["hydro_data"]["hydro"] = Dict(i => data["hydro_data"]["hydro"][i] for i in keys(data["hydro_data"]["hydro"]) if i in selected_nodes)

    # network data
    data["line_to"] = Dict(i => data["line_to"][i] for i in keys(data["line_to"]) if i in selected_nodes)
    data["line_data"] = Dict(i => data["line_data"][i] for i in keys(data["line_data"]) if i in selected_nodes)
    data["line_from"] = Dict(i => data["line_from"][i] for i in keys(data["line_from"]) if i in selected_nodes)

    data["line_to"] = Dict(i => [j for j in data["line_to"][i] if j in selected_nodes] for i in keys(data["line_to"]))
    data["line_from"] = Dict(i => [j for j in data["line_from"][i] if j in selected_nodes] for i in keys(data["line_from"]))
    data["line_data"] = Dict(i => Dict(j => data["line_data"][i][j] for j in keys(data["line_data"][i]) if j in selected_nodes) for i in keys(data["line_data"]))

    data["line_from_keys"] = [i for i in data["line_from_keys"] if (i in selected_nodes && length(data["line_from"][i])>0)]
    data["line_to_keys"] = [i for i in data["line_to_keys"] if (i in selected_nodes && length(data["line_to"][i])>0)]

    return data
end

function erase_some_nodes(data, erase_nodes)
    data["generators_new_keys"] = [i for i in data["generators_new_keys"] if !(i in erase_nodes)]
    data["generators_exist_keys"] = [i for i in data["generators_exist_keys"] if !(i in erase_nodes)]
    data["node_hydro"]["PS Closed"] = [i for i in data["node_hydro"]["PS Closed"] if !(i in erase_nodes)]
    data["node_hydro"]["PS Open"] = [i for i in data["node_hydro"]["PS Open"] if !(i in erase_nodes)]
    data["node_hydro"]["Reservoir"] = [i for i in data["node_hydro"]["Reservoir"] if !(i in erase_nodes)]
    data["dsr_keys"] = [i for i in data["dsr_keys"] if !(i in erase_nodes)]
    data["node_battery"] = [i for i in data["node_battery"] if !(i in erase_nodes)]
    data["nodes"] = [i for i in data["nodes"] if !(i in erase_nodes)]

    data["generators_exist"] = Dict(i => data["generators_exist"][i] for i in data["generators_exist_keys"])
    data["dsr_data"] = Dict(i => data["dsr_data"][i] for i in keys(data["dsr_data"]) if !(i in erase_nodes))
    data["dsr"] = Dict(i => data["dsr"][i] for i in keys(data["dsr"]) if !(i in erase_nodes))
    data["battery_data"] = Dict(i => data["battery_data"][i] for i in keys(data["battery_data"]) if !(i in erase_nodes))
    data["load"] = Dict(i => data["load"][i] for i in keys(data["load"]) if !(i in erase_nodes))
    data["generators_new"] = Dict(i => data["generators_new"][i] for i in data["generators_new_keys"])
    data["generators_data"]["New"] = Dict(i => data["generators_data"]["New"][i] for i in keys(data["generators_data"]["New"]) if !(i in erase_nodes))
    data["generators_data"]["Exist"] = Dict(i => data["generators_data"]["Exist"][i] for i in keys(data["generators_data"]["Exist"]) if !(i in erase_nodes))
    data["hydro_data"]["hydro_storage"] = Dict(i => data["hydro_data"]["hydro_storage"][i] for i in keys(data["hydro_data"]["hydro_storage"]) if !(i in erase_nodes))
    data["hydro_data"]["hydro"] = Dict(i => data["hydro_data"]["hydro"][i] for i in keys(data["hydro_data"]["hydro"]) if !(i in erase_nodes))

    # network data
    data["line_to"] = Dict(i => data["line_to"][i] for i in keys(data["line_to"]) if !(i in erase_nodes))
    data["line_data"] = Dict(i => data["line_data"][i] for i in keys(data["line_data"]) if !(i in erase_nodes))
    data["line_from"] = Dict(i => data["line_from"][i] for i in keys(data["line_from"]) if !(i in erase_nodes))

    data["line_to"] = Dict(i => [j for j in data["line_to"][i] if !(j in erase_nodes)] for i in keys(data["line_to"]))
    data["line_from"] = Dict(i => [j for j in data["line_from"][i] if !(j in erase_nodes)] for i in keys(data["line_from"]))
    data["line_data"] = Dict(i => Dict(j => data["line_data"][i][j] for j in keys(data["line_data"][i]) if !(j in erase_nodes)) for i in keys(data["line_data"]))

    data["line_from_keys"] = [i for i in data["line_from_keys"] if (!(i in erase_nodes) && length(data["line_from"][i])>0)]
    data["line_to_keys"] = [i for i in data["line_to_keys"] if (!(i in erase_nodes) && length(data["line_to"][i])>0)]

    return data
end

function create_lump_fiels(data, data_path)
    # load the lumps_technos file
    Lumps_dataframe = CSV.read(data_path, DataFrame)
    Lumps = Dict(Lumps_dataframe[i,:Column1] => Lumps_dataframe[i,:lump] for i in 1:length(Lumps_dataframe[:,:Column1]))
    for i in data["generators_new_keys"]
        for g in data["generators_new"][i]
            data["generators_data"]["New"][i][g]["Lumps"] = Lumps[g]
        end
    end
    for i in data["generators_exist_keys"]
        for g in data["generators_exist"][i]
            data["generators_data"]["Exist"][i][g]["Lumps"] = Lumps[g]
        end
    end
    return data
end

function load_initial_solution(initial_solution_path)
    x_new = JSON.parsefile(initial_solution_path*"x_new.json")
    x_exist = JSON.parsefile(initial_solution_path*"x_exist.json")
    p_new = JSON.parsefile(initial_solution_path*"p_new.json")
    p_exist = JSON.parsefile(initial_solution_path*"p_exist.json")
    return Dict("x_new"=>x_new, "x_exist"=>x_exist, "p_new"=>p_new, "p_exist"=>p_exist)
end

"""
Change the max possible installable capacity (default was 10 GW). 
data_path is the path to the file containing those data.
"""
function change_max_commissionning_capa(data, data_path)
    println("Changing the maximum commissionning limits...")
    max_capa_data = CSV.read(data_path, DataFrame)
    max_capa = Dict(max_capa_data[i,:Column1] => 
        Dict("Gas/CCGT new"=>max_capa_data[i,:max_installable_CCGT],
            "Gas/OCGT new"=>max_capa_data[i,:max_installable_OCGT]) for i in 1:length(max_capa_data[:,:Column1]))
    for i in data["nodes"]
        for g in keys(data["generators_data"]["New"][i])
            data["generators_data"]["New"][i][g]["CapaMax"] = max_capa[i][g]
        end
    end

    return data
end
