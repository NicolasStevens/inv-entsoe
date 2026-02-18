#=
main:
- Julia version: 1.5.3
- Author: Nicolas
- Date: 2022-05-09
=#
using JuMP
import LinearAlgebra
using Printf
import Test
import Gurobi
using DataFrames
using Plots
#PyPlot()
gr(size = (1000, 600), legend = true)  # provide optional defaults
using StatsPlots
#Plots.scalefontsizes(2.5)
using JSON
using ProgressMeter
using CSV
using Statistics
using StatsPlots


const GUROBI_ENV = Gurobi.Env()  # this is to avoid having msgs from Gurobi all the time
println("")
include("EVA_continuous.jl")
include("EVA_discrete.jl")
include("EVA_capacity_market.jl")
include("EVA_capacity_market_elastic.jl")
include("load_data.jl")
include("lib_plot.jl")
include("agents_subproblem.jl")
include("agents_subproblem_discrete.jl")
include("EVA_CminNational.jl")
include("EVA_CminNational2.jl")
println("")

# This is the main code that launches all the simulations for computing the national Cmin estimates

################################################################################
### User Parameters
################################################################################
# YEARS for 2025:
# first simu: [1989, 1990, 1994, 1996, 2010, 2012, 2014, 2016]
# new simu: [1982, 1983, 1984, 1985, 1986, 1987, 1991, 1992, 1993, 1995, 1997, 1998, 1999, 2001, 2002, 2003, 2004, 2007, 2008, 2009, 2010, 2011, 2013, 2015]
# YEARS for 2030
# first simu: [1983, 1984, 1989, 1990, 1991, 1992, 1996, 1997, 2001, 2002, 2014, 2015, 2016]
# new simu: [1982, 1985, 1988, 1993, 1995, 1998, 1999, 2000, 2003, 2004, 2007, 2008, 2010, 2011, 2012, 2013]
target_year_all = [2025] # either 2025 or 2030
year_all = [1989, 1990, 1994, 1996, 2010, 2012, 2014, 2016, 1982, 1983, 1984, 1985, 1986, 1987, 1991, 1992, 1993, 1995, 1997, 1998, 1999, 2001, 2002, 2003, 2004, 2007, 2008, 2009, 2011, 2013, 2015] #reverse([(1981+i) for i in 1:35]) # 2016
CO2_price = 0.04 # This correcponds to 40€/ton of CO2
VOLL = 15000
selected_nodes = "all" # "all", "cwe"
erase_nodes_list = ["TR00"] # set to 0 to not erase any node
folder_path = "/Users/Nicolas/Documents/Mesdocuments/1Travaux/UCL/PhD/Investment_code"

for target_year in target_year_all
    for year in year_all
        model_name = "national_discrete"
        case_study_name = "$(year)_$(selected_nodes)_$(model_name)_target$(target_year)" #"all_discrete_crm", "all_continuous"
        println("Solving the model $model_name for target year $target_year using CY $year.")

        data_path = "$(folder_path)/data/"
        save_path = "out/"

        # Data loading and processing
        data = load_data("$data_path/json_data$target_year/", year, CO2_price, VOLL)
        if erase_nodes_list!=0
            println("Erasing nodes $erase_nodes_list.")
            data = erase_some_nodes(data, erase_nodes_list)
        end
        # changing the capacity limits
        data = change_max_commissionning_capa(data, "$data_path/max_gas_installable_capacity.csv")
        data = create_lump_fiels(data, "$data_path/lumps_technos.csv")
        # Data analysis
        if (isdir("$save_path$case_study_name")==0) mkdir("$save_path$case_study_name") end
        solve_EVAnational_discrete2(data, "$save_path$case_study_name")
    end
end
