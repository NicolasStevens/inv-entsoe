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
println("")

# This is the main code that launches all the simulations

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
year_all = [2014]#[1989, 1990, 1994, 1996, 2010, 2012, 2016, 1982, 1983, 1984, 1985, 1986, 1987, 1991, 1992, 1993, 1995, 1997, 1998, 1999, 2001, 2002, 2003, 2004, 2007, 2008, 2009, 2011, 2013, 2015] #reverse([(1981+i) for i in 1:35]) # 2016
CO2_price = 0.04 # This correcponds to 40€/ton of CO2
VOLL = 15000

model_type_all = [2]

save_input_figures = 0 # set to 1 in order to generate plots of the inputs
save_output_solution = 1 # set to 1 in otder to save the model solution in json files
save_output_figures = 1 # set to 1 in order to generate plots of the output

elastic_CRM = 0 # set to 1 to run the elastic CRM model, 0 for the inelastic demand curve
CRM_with_national_targets = 0 # set to 1 to define the Cmin target as the national estimates

selected_nodes = "all" # "all", "cwe"
erase_nodes_list = ["TR00"] # set to 0 to not erase any node

folder_path = "/Users/Nicolas/Documents/Mesdocuments/1Travaux/UCL/PhD/Investment_code"

for target_year in target_year_all
    for year in year_all
        for model_type in model_type_all
            if model_type==0
                discrete_model = 0
                CRM_included = 0
                solve_CRM_from_discrete = 0
            elseif model_type==1
                discrete_model = 1
                CRM_included = 0
                solve_CRM_from_discrete = 0
            else
                discrete_model = 1
                CRM_included = 1
                solve_CRM_from_discrete = 1
            end
            ################################################################################
            discrete_solution_path = "$(folder_path)/InvCode/out/$(target_year)discrete/$(year)_all_discrete_target$(target_year)/solution/"
            initial_solution = Nothing
            data_path = "$(folder_path)/data/"
            save_path = "out/"
            if discrete_model==0 
                model_name = "continuous"
            elseif discrete_model==1 && CRM_included==0
                model_name = "discrete"
            else
                model_name = "discrete_crm"
            end
            case_study_name = "$(year)_$(selected_nodes)_$(model_name)_target$(target_year)" #"all_discrete_crm", "all_continuous"

            println("Solving the model $model_name for target year $target_year using CY $year.")
            ################################################################################
            ### Main code
            # Data loading and processing
            data = load_data("$data_path/json_data$target_year/", year, CO2_price, VOLL)
            if erase_nodes_list!=0
                println("Erasing nodes $erase_nodes_list.")
                data = erase_some_nodes(data, erase_nodes_list)
            end
            # changing the capacity limits
            data = change_max_commissionning_capa(data, "$data_path/max_gas_installable_capacity.csv")
            # Data analysis
            if (save_input_figures+save_output_solution+save_output_figures>0 && isdir("$save_path$case_study_name")==0) mkdir("$save_path$case_study_name") end
            if save_input_figures==1
                println("Saving input figures...")
                if isdir("$save_path$case_study_name/input_analysis")==0 mkdir("$save_path$case_study_name/input_analysis") end
                plot_OCexist_per_techno(data, "$save_path$case_study_name/input_analysis", 1)
                plot_OCnew_per_techno(data, "$save_path$case_study_name/input_analysis", 1)
                plot_ICexist_per_techno(data, "$save_path$case_study_name/input_analysis", 1)
                plot_ICnew_per_techno(data, "$save_path$case_study_name/input_analysis", 1)
                plot_load_boxplot(data, "$save_path$case_study_name/input_analysis", 1)
                plot_max_capa_new(data, "$save_path$case_study_name/input_analysis", 1)
                plot_max_capa_exist(data, "$save_path$case_study_name/input_analysis", 1)
            end
            # Model solving
            if discrete_model==1
                println("Solving the DISCRETE investment problem")
                println("Adding the lumps data")
                data = create_lump_fiels(data, "$data_path/lumps_technos.csv")
                if CRM_included==1
                    println("Solving the problem WITH CRM")
                    if solve_CRM_from_discrete==1
                        if elastic_CRM==0 && CRM_with_national_targets==0
                            results = solve_EVA_discrete_CRM_only(data, discrete_solution_path)
                        elseif CRM_with_national_targets==1
                            println("Solving the CRM with the NATIONAL capacity targets")
                            Cmin_solution_path = "$(folder_path)/InvCode/out/$(target_year)discrete_nat/$(year)_all_national_discrete_target$(target_year)/"
                            results = solve_EVA_discrete_CRM_only2(data, discrete_solution_path, Cmin_solution_path)
                        else
                            println("Solving the CRM with ELASTIC capacity demand curve")
                            results = solve_EVA_discrete_CRM_Elastic_only(data, discrete_solution_path, "$save_path$case_study_name/")
                        end
                        x_new = results["x_new"]
                        x_exist = results["x_exist"]
                    else
                        results = solve_EVA_discrete_CRM(data, nothing)
                        x_new = value.(results["EVA_model"][:x_new])
                        x_exist = value.(results["EVA_model"][:x_exist])
                    end
                    C_prices = results["C_prices"]
                else
                    println("Solving the problem WITHOUT CRM")
                    results = solve_EVA_discrete(data, initial_solution)
                    x_new = value.(results["EVA_model"][:x_new])
                    x_exist = value.(results["EVA_model"][:x_exist])
                end
                TEI = results["TEI"]
            else
                println("Solving the CONTINUOUS investment problem")
                results = solve_EVA_continuous(data, initial_solution)
                x_new = value.(results["EVA_model"][:x_new])
                x_exist = value.(results["EVA_model"][:x_exist])
                # in order to solve the "ip" version of continuous investment, replace by: solve_EVA_continuous2(data, initial_solution)
                TEI = 0.0
            end
            EVA_model = results["EVA_model"]
            run_time = results["run_time"]
            total_costs = results["total_costs"]
            Profits = results["Profits"]
            E_price = results["E_prices"]
            println(comp_total_loc_mwp(Profits, "New"))
            println(comp_total_loc_mwp(Profits, "Exist"))
            if save_output_solution==1
                if isdir("$save_path$case_study_name/solution")==0 mkdir("$save_path$case_study_name/solution") end
                if CRM_included==1
                    save_model_solution(data, EVA_model, E_price, Profits, "$save_path$case_study_name/solution/",C_prices, solve_CRM_from_discrete)
                else
                    save_model_solution(data, EVA_model, E_price, Profits, "$save_path$case_study_name/solution/")
                end
            end
            # Model solution analysis
            if save_output_figures==1
                if isdir("$save_path$case_study_name/output_analysis")==0 mkdir("$save_path$case_study_name/output_analysis") end
                writeRunSummary(EVA_model, x_new, data, Profits, total_costs, run_time, TEI, discrete_model, "$save_path$case_study_name/output_analysis", 1, solve_CRM_from_discrete)
                write_latextable_profitExist(data, Profits, x_exist, "$save_path$case_study_name/output_analysis/ExistGenProfitsLOC_$case_study_name.tex", discrete_model)
                write_latextable_profitNew(data, Profits, x_new, "$save_path$case_study_name/output_analysis/NewGenProfitsLOC_$case_study_name.tex", discrete_model)
                if solve_CRM_from_discrete !=1
                    plot_load_shedding_sum(value.(EVA_model[:slack_neg]), value.(EVA_model[:slack_pos]), data, "$save_path$case_study_name/output_analysis", 1)
                    plot_load_shedding_num(value.(EVA_model[:slack_neg]), value.(EVA_model[:slack_pos]), data, "$save_path$case_study_name/output_analysis", 1)
                    plot_netposition_boxplot(value.(EVA_model[:flow]), data, "$save_path$case_study_name/output_analysis", 1)
                    plot_price_boxplot(E_price, data, 2, "$save_path$case_study_name/output_analysis", 1)
                end
                if discrete_model==1
                    if solve_CRM_from_discrete !=1
                        plot_x_new_discrete(value.(EVA_model[:x_new]), data, "New Investments", "", "MW", "$save_path$case_study_name/output_analysis", 1)
                        plot_x_exist_discrete(value.(EVA_model[:x_exist]), data, "Plant Retirements", "", "MW", "$save_path$case_study_name/output_analysis", 1)
                    end
                    plot_loc(Profits, "New", "$save_path$case_study_name/output_analysis", 1)
                    plot_loc(Profits, "Exist", "$save_path$case_study_name/output_analysis", 1)
                    if CRM_included==1
                        plot_Cprice(Dict(i=>C_prices[i] for i in data["nodes"]), "$save_path$case_study_name/output_analysis", 1)
                    end
                    if solve_CRM_from_discrete!=1
                        active_prod = compute_percent_active(data, value.(EVA_model[:p_new]), value.(EVA_model[:p_exist]), value.(EVA_model[:x_new]), value.(EVA_model[:x_exist]))
                        set_price = compute_percent_setprice(data, value.(EVA_model[:p_new]), value.(EVA_model[:p_exist]), value.(EVA_model[:x_new]), value.(EVA_model[:x_exist]), E_price)
                        plot_active_prod_boxplot(active_prod, "Percentage of Time a Technology is Running (Distribution across Nodes)",
                            "$save_path$case_study_name/output_analysis", "active_prod_boxplot", 1)
                        plot_active_prod_boxplot(set_price, "Percentage of Time a Technology Sets the Price (Distribution across Nodes)",
                            "$save_path$case_study_name/output_analysis", "set_price_boxplot", 1)
                    end
                else
                    plot_x_new(value.(EVA_model[:x_new]), data, "New Investments", "", "MW", "$save_path$case_study_name/output_analysis", 1)
                    plot_x_exist(value.(EVA_model[:x_exist]), data, "Plant Retirements", "", "MW", "$save_path$case_study_name/output_analysis", 1)
                end 
            end
        end
    end
end
