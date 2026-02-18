############################################
#### HLDC formulation
############################################

function stage_1(model::Model, NOmegas::Int64)

   ################################
   ###### First stage variables

   @variable(model, 0 <= x[plan in expansion_plan, code in codes_plan[plan], generators_type[plan][code] ]) # Candidate projects.

   ################################
   ###### Objective function

   add_stage_1_objective!(model)

   ################################
   ###### First stage

   for code in ExpantionCodes
      for g in keys(Generators["New"][code])
         cap = Generators["New"][code][g]["Max Capacity"]
         units = Generators["New"][code][g]["Max Units Built"]
         if code == "FR00"
            units = 10000
            cap = 1
         end

         @constraint(model, x["Invest",code,g] <= cap*units)
      end
   end

   for code in Codes
      for g in generators_type["Retire"][code]
         cap = Generators["Exist"][code][g]["Rating"]
         mincap = Generators["Exist"][code][g]["Min Load"]
         max_cap = Generators["Exist"][code][g]["Retire capacity"]

         if cap[1] > 0
            val = max_cap*(1-mincap[1]/cap[1])
         else
            val = max_cap
         end

         for t in 1:T
            if cap[t] > 0
               f = mincap[t]/cap[t]
            else
               f = 0
            end

            curr_val = max_cap*(1-f)
            if curr_val < val
               val = curr_val
            end
         end

         val_bound = val

         if val_bound < 0.0
            val_bound = 0.0
         end

         @constraint(model, x["Retire",code,g] <= val_bound)
      end
   end
end

function stage_2(model::Model, NOmegas::Int64)

   ################################
   ###### Second stage variables

   # Hydro
   @variable(model, 0 <= q[1:T, code in Codes, g in keys(hydro[code]), 1:NOmegas] ) # This variable will account for the hydro production for each technology
   @variable(model, 0 <= s[1:T, code in Codes, g in keys(hydro[code]), 1:NOmegas] ) # This variable will account for the spillage for each technology
   @variable(model, 0 <= v[1:T, code in Codes, g in keys(hydro[code]), storage in keys(hydro_storage[code][g]), 1:NOmegas] ) # This variable will account for the stored energy for each technology
   @variable(model, 0 <= d[1:T, code in Codes, g in intersect( keys(hydro[code]), ["PS Closed", "PS Open"] ), 1:NOmegas] ) # This variable will account for the pumped energy for pumped storage

   # Batteries
   @variable(model, 0 <= bc[1:T, code in Codes, g in keys(battery[code]), 1:NOmegas] ) # This variable will account for the battery charge
   @variable(model, 0 <= bd[1:T, code in Codes, g in keys(battery[code]), 1:NOmegas] ) # This variable will account for the battery charge
   @variable(model, 0 <= bv[1:T, code in Codes, g in keys(battery[code]), 1:NOmegas] ) # This variable will account for the battery storage

   # Existing generation units
   @variable(model, 0 <= p[1:T, code in Codes, Generator_category_node[code], 1:NOmegas])

   # New Generating units
   @variable(model, 0 <= p_new[1:T, code in ExpantionCodes, keys(Generators["New"][code]), 1:NOmegas])

   # DSR
   @variable(model, 0 <= p_DSR[1:T, code in Codes, n in keys(DSR[code]), 1:NOmegas])

   # Other variables
   @variable(model, 0 <= ls[1:T, Codes, 1:NOmegas])
   @variable(model, 0 <= ps[1:T, Codes, 1:NOmegas])

   # Lines
   @variable(model, 0 <= fAC_p[1:T, code in Codes, toCode in keys(LinesFrom["HVAC"][code]), LinesFrom["HVAC"][code][toCode], 1:NOmegas])
   @variable(model, 0 <= fAC_n[1:T, code in Codes, toCode in keys(LinesFrom["HVAC"][code]), LinesFrom["HVAC"][code][toCode], 1:NOmegas])
   @variable(model, 0 <= fDC_p[1:T, code in Codes, toCode in keys(LinesFrom["HVDC"][code]), LinesFrom["HVDC"][code][toCode], 1:NOmegas])
   @variable(model, 0 <= fDC_n[1:T, code in Codes, toCode in keys(LinesFrom["HVDC"][code]), LinesFrom["HVDC"][code][toCode], 1:NOmegas])

   # Indicator variable of ls
   if reliability == true
      @variable(model, inls[1:T, reliability_nodes, 1:NOmegas], Bin)
   end

   # Parametrization variables
   @variable(model, ParamLoad[1:T, Codes, 1:NOmegas] == 0.0, Param())
   @variable(model, ParamDemand[1:T, Codes, 1:NOmegas] == 0.0, Param())

   ################################
   ###### Objective function

   add_stage_2_objective!(model, NOmegas)

   ################################
   ###### Second stage

   ################################
   ###### Hydro Modeling

   parametrization = true
   add_hydro_constraints!(model, NOmegas, parametrization)

   ################################
   ###### Battery Modeling

   add_batteries_constraints!(model, NOmegas)

   ################################
   ###### Load balance constraint

   add_load_balance_constraint!(model, NOmegas)

   ###########################################
   ###### Maximum & Minimum power generation

   add_generator_constraints!(model, NOmegas)

   ################################
   ###### Maximum & Minimum NTC

   add_lines_constraints!(model, NOmegas)

   ################################
   ###### Realibility
   if reliability == true
      add_reliability_constraints!(model, NOmegas)
   end
end

############################################
#### Functions to add objective
############################################

function add_stage_1_objective!(model::Model)
   x = model[:x] # Investment cost
   @expression(model, objective_expression, sum( (Generators["New"][code][g]["Annualized Build Cost"]
   + Generators["New"][code][g]["FO&M Charge"]*1000)*x["Invest", code, g] for code in ExpantionCodes, g in keys(Generators["New"][code]))
   - sum(Generators["Exist"][code][g]["FO&M Charge"]*1000*x["Retire", code, g] for code in Codes, g in generators_type["Retire"][code] )
   )
   @objective(model, Min, objective_expression)
end

function add_stage_2_objective!(model::Model, NOmegas::Int64)
   p = model[:p] # Existing generation units
   p_new = model[:p_new] # New Generating units
   p_DSR = model[:p_DSR] # DSR
   ls = model[:ls] # load shedding
   s = model[:s] # spillage

   fAC_p = model[:fAC_p] # lines AC positive part
   fAC_n = model[:fAC_n] # lines AC negative part

   fDC_p = model[:fDC_p] # lines DC positive part
   fDC_n = model[:fDC_n] # lines DC negative part

   ################################
   ###### Objective function

   if reliability == false
      loadshedding = @expression(model, sum(ls[t,code,omega]*Probabilities[omega]*Duration[code][t] for t in 1:T, code in Codes, omega in 1:NOmegas)*VOLL )
   else
      loadshedding = @expression(model, sum(ls[t,code,omega]*Probabilities[omega]*Duration[code][t] for t in 1:T, code in setdiff(Codes, reliability_nodes), omega in 1:NOmegas)*VOLL )
   end

   @objective(model, Min,

   # Second stage
   + loadshedding  # Load shedding

   + sum(DSR[code][n]["Offer Price"]*p_DSR[t,code,n,omega]*(Duration[code][t]) # DSR (€/MWh MW h)
   for t in 1:T, code in Codes, n in keys(DSR[code]), omega in 1:NOmegas)

   # Hydro spill penalty
   + sum((hydro_storage[code][g]["Head Storage"]["Spill Penalty"]/1000)*s[t,code,g,omega]*(Duration[code][t]) # Hydro (€/MWh MW h)
   for t in 1:T, code in Codes, g in intersect(keys(hydro_storage[code]), ["Reservoir", "PS Closed", "PS Open"]), omega in 1:NOmegas)

   # Existing generators
   + sum(Generators["Exist"][code][g]["VO&M Charge"]*p[t,code,g,omega]*(Duration[code][t])*Probabilities[omega]
   for t in 1:T, code in Codes, g in Generator_category_node[code], omega in 1:NOmegas) # VO&M Charge (€/MWh MW h)

   + sum(Fuels[Generators["Exist"][code][g]["Fuel Type"]]["Price"]*Generators["Exist"][code][g]["Heat Rate"]*p[t,code,g,omega]*(Duration[code][t])*Probabilities[omega]
   for t in 1:T, code in Codes, g in Generator_category_node[code], omega in 1:NOmegas) # Fuel consumption (€/GJ GJ/MWh MW h)

   + sum(Emissions["CO2"]["Price"]*Fuels[Generators["Exist"][code][g]["Fuel Type"]]["Production Rate"]*Generators["Exist"][code][g]["Heat Rate"]*p[t,code,g,omega]*(Duration[code][t])*Probabilities[omega]
   for t in 1:T, code in Codes, g in Generator_category_node[code], omega in 1:NOmegas) # Emissions (€/kg kg/GJ GJ/MWh MW h)

   # New generators
   + sum(Generators["New"][code][g]["VO&M Charge"]*p_new[t,code,g,omega]*(Duration[code][t])*Probabilities[omega]
   for t in 1:T, code in ExpantionCodes, g in keys(Generators["New"][code]), omega in 1:NOmegas) # New VO&M Charge (€/MWh MW h)

   + sum(Fuels[Generators["New"][code][g]["Fuel Type"]]["Price"]*Generators["New"][code][g]["Heat Rate"]*p_new[t,code,g,omega]*(Duration[code][t])*Probabilities[omega]
   for t in 1:T, code in ExpantionCodes, g in keys(Generators["New"][code]), omega in 1:NOmegas) # New Fuel consumption (€/GJ GJ/MWh MW h)

   + sum(Emissions["CO2"]["Price"]*Fuels[Generators["New"][code][g]["Fuel Type"]]["Production Rate"]*Generators["New"][code][g]["Heat Rate"]*p_new[t,code,g,omega]*(Duration[code][t])*Probabilities[omega]
   for t in 1:T, code in ExpantionCodes, g in keys(Generators["New"][code]), omega in 1:NOmegas) # New Emissions (€/kg kg/GJ GJ/MWh MW h)

   # Transmision line cost
   + sum(Lines["HVAC"][code][toCode][n]["Wheeling Charge"]*fAC_p[t,code,toCode,n,omega]*(Duration[code][t])*Probabilities[omega]
   for t in 1:T, code in Codes, toCode in keys(LinesFrom["HVAC"][code]), n in LinesFrom["HVAC"][code][toCode], omega in 1:NOmegas) # AC positive charge (€/MWh MW h)

   + sum(Lines["HVAC"][code][toCode][n]["Wheeling Charge"]*fAC_n[t,code,toCode,n,omega]*(Duration[code][t])*Probabilities[omega]
   for t in 1:T, code in Codes, toCode in keys(LinesFrom["HVAC"][code]), n in LinesFrom["HVAC"][code][toCode], omega in 1:NOmegas) # AC negative charge (€/MWh MW h)

   + sum(Lines["HVDC"][code][toCode][n]["Wheeling Charge"]*fDC_p[t,code,toCode,n,omega]*(Duration[code][t])*Probabilities[omega]
   for t in 1:T, code in Codes, toCode in keys(LinesFrom["HVDC"][code]), n in LinesFrom["HVDC"][code][toCode], omega in 1:NOmegas) # DC positive charge (€/MWh MW h)

   + sum(Lines["HVDC"][code][toCode][n]["Wheeling Charge"]*fDC_n[t,code,toCode,n,omega]*(Duration[code][t])*Probabilities[omega]
   for t in 1:T, code in Codes, toCode in keys(LinesFrom["HVDC"][code]), n in LinesFrom["HVDC"][code][toCode], omega in 1:NOmegas) # DC negative charge (€/MWh MW h)
   );
end

############################################
#### Functions to add constraints
############################################

################################
###### Second stage constraints

function add_hydro_constraints!(model::Model, NOmegas::Int64, parametrization::Bool)
   q = model[:q]
   s = model[:s]
   v = model[:v]
   d = model[:d]

   if parametrization == true
      # Parametrization of the uncertainity parameters
      @variable(model, natural_inflow[1:T, code in Codes, g in keys(hydro[code]), 1:NOmegas] )# == 0.0, Param())
      @variable(model, initial_volume[code in Codes, g in keys(hydro[code]), storage in keys(hydro_storage[code][g]), 1:NOmegas] )# == 0.0, Param())
      @variable(model, rating[1:T, code in Codes, g in keys(hydro[code]), 1:NOmegas] )# == 0.0, Param())
      @variable(model, min_load[1:T, code in Codes, g in keys(hydro[code]), 1:NOmegas] )# == 0.0, Param())
      @variable(model, pump_load[1:T, code in Codes, g in intersect( keys(hydro[code]), ["PS Closed", "PS Open"]), 1:NOmegas] )# == 0.0, Param())
   end

   ################################
   ###### Hydro Modeling
   for omega = 1:NOmegas
      CY = Omegas[omega]
      climatic_year = climate_years["Names"][CY]

      for code in Codes
         for t in 1:T
            if "Run-of-River" in keys(hydro[code])
               if parametrization == true
                  natural_inflow_val = natural_inflow[t, code,"Run-of-River", omega]
               else
                  natural_inflow_val = hydro_storage[code]["Run-of-River"]["Head Storage"]["Natural Inflow"][climatic_year][t]
               end

               # Properties of hydro_storage:
               # Head Storage:
               ## End Effects Method: Not modeled
               ## End Volume Coefficient: Not modeled
               ## Target Year: Not modeled (The data is assumed to load the target year)
               ## Max Volume: Not modeled (Used when laoding the data to determine if corresponds to Reservoir or Run-of-River)
               ## Target Penalty: Not modeled
               ## Initial Volume: Not modeled (Used when laoding the data to determine if corresponds to Reservoir or Run-of-River)
               ## Spill Penalty: Not modeled (All the natural inflows are used as energy produced as there is no storage)
               ## Natrual Inflow: added as produced energy

               @constraint(model, q[t,code,"Run-of-River",omega] == natural_inflow_val)
            end

            if "Reservoir" in keys(hydro[code])

               if parametrization == true
                  natural_inflow_val = natural_inflow[t, code,"Reservoir",omega]
                  initial_volume_val = initial_volume[code,"Reservoir","Head Storage",omega]
                  rating_val = rating[t, code,"Reservoir", omega]
                  min_load_val = min_load[t, code,"Reservoir", omega]
               else
                  natural_inflow_val = hydro_storage[code]["Reservoir"]["Head Storage"]["Natural Inflow"][climatic_year][t]
                  initial_volume_val = get_vale(hydro_storage[code]["Reservoir"]["Head Storage"]["Initial Volume"], climatic_year, t)

                  if "Rating" in keys(hydro[code]["Reservoir"])
                     rating_val = get_vale(hydro[code]["Reservoir"]["Rating"], climatic_year, t)
                  else
                     rating_val = hydro[code]["Reservoir"]["Max Capacity"]
                  end

                  if "Min Load" in keys(hydro[code]["Reservoir"])
                     min_load_val = get_vale(hydro[code]["Reservoir"]["Min Load"], climatic_year, t)
                  else
                     min_load_val = 0.0
                  end
               end

               # Properties of hydro_storage:
               # Head Storage:
               ## End Effects Method: Not modeled
               ## End Volume Coefficient: Not modeled
               ## Target Year: Not modeled (the data is assumed to load the target year)
               ## Max Volume: Modeled (added as upper constraint on v, multiplied by 1000 to go GW to MW)
               ## Target Penalty: Not modeled
               ## Initial Volume: Modeled (added as initial condition on v, multiplied by 1000 to go GWh to MWh)
               ## Spill Penalty: Modeled (Penalized in the objective, divided by 1000 to go from $/GWh to $/MWh)
               ## Natrual Inflow: Modeled (added as energy that arrivees to the reservoir)

               if t == 1
                  @constraint(model, v[t,code,"Reservoir","Head Storage",omega] == initial_volume_val*1000/Duration[code][t] + natural_inflow_val - q[t,code,"Reservoir",omega] - s[t,code,"Reservoir",omega])
               else
                  @constraint(model, v[t,code,"Reservoir","Head Storage",omega] == v[t-1,code,"Reservoir","Head Storage",omega] + natural_inflow_val - q[t,code,"Reservoir",omega] - s[t,code,"Reservoir",omega])
               end

               @constraint(model, v[t,code,"Reservoir","Head Storage",omega] <= hydro_storage[code]["Reservoir"]["Head Storage"]["Max Volume"]*1000)

               # Properties of hydro:
               ## Units: Not modeled (Always assumed is 1)
               ## Max Capacity: Modeled if no rating is included (added as upper bound on q)
               ## Rating: Modeled (added as upper bound on q)
               ## Min Load: Modeled (added as lower bound on q)

               @constraint(model, q[t,code,"Reservoir",omega] <= rating_val)
               @constraint(model, q[t,code,"Reservoir",omega] >= 0.0)#min_load_val)
            end

            if "PS Closed" in keys(hydro[code])

               if parametrization == true
                  initial_volume_head_val = initial_volume[code,"PS Closed","Head Storage",omega]
                  initial_volume_tail_val = initial_volume[code,"PS Closed","Tail Storage",omega]
                  rating_val = rating[t, code,"PS Closed", omega]
                  min_load_val = min_load[t, code,"PS Closed", omega]
                  pump_load_val = pump_load[t, code,"PS Closed", omega]
               else
                  initial_volume_head_val = get_vale(hydro_storage[code]["PS Closed"]["Head Storage"]["Initial Volume"], climatic_year, t)
                  initial_volume_tail_val = get_vale(hydro_storage[code]["PS Closed"]["Tail Storage"]["Initial Volume"], climatic_year, t)

                  if "Rating" in keys(hydro[code]["PS Closed"])
                     rating_val = get_vale(hydro[code]["PS Closed"]["Rating"], climatic_year, t)
                  else
                     rating_val = hydro[code]["PS Closed"]["Max Capacity"]
                  end

                  if "Min Load" in keys(hydro[code]["PS Closed"])
                     min_load_val = get_vale(hydro[code]["PS Closed"]["Min Load"], climatic_year, t)
                  else
                     min_load_val = 0.0
                  end

                  pump_load_val = get_vale(hydro[code]["PS Closed"]["Pump Load"], climatic_year, t)
               end

               # Properties of hydro_storage:
               # Head Storage:
               ## End Effects Method: Not modeled
               ## Target penalty: Not modeled
               ## Target Year: Not modeled (the data is assumed to load the target year)
               ## Max Volume: Modeled (added as upper constraint on v, multiplied by 1000 to go GW to MW)
               ## Initial Volume: Modeled (added as initial condition on v, multiplied by 1000 to go GWh to MWh)
               ## Spill Penalty: Modeled (Penalized in the objective, divided by 1000 to go from $/GWh to $/MWh)

               efficiency = hydro[code]["PS Closed"]["Pump Efficiency"]/100

               if t == 1
                  @constraint(model, v[t,code,"PS Closed","Head Storage",omega] == initial_volume_head_val*1000/Duration[code][t] + efficiency*d[t,code,"PS Closed",omega] - q[t,code,"PS Closed",omega] - s[t,code,"PS Closed",omega])
               else
                  @constraint(model, v[t,code,"PS Closed","Head Storage",omega] == v[t-1,code,"PS Closed", "Head Storage", omega] + efficiency*d[t,code,"PS Closed",omega] - q[t,code,"PS Closed",omega] - s[t,code,"PS Closed",omega])
               end

               @constraint(model, v[t,code,"PS Closed","Head Storage",omega] <= hydro_storage[code]["PS Closed"]["Head Storage"]["Max Volume"]*1000)

               # Tail Storage:
               ## End Effects Method: Not modeled
               ## Initial Volume: Modeled (added as initial condition on v, multiplied by 1000 to go GWh to MWh)

               if t == 1
                  @constraint(model, v[t,code,"PS Closed","Tail Storage",omega] == initial_volume_tail_val*1000/Duration[code][t] + q[t,code,"PS Closed",omega] - efficiency*d[t,code,"PS Closed",omega] )
               else
                  @constraint(model, v[t,code,"PS Closed","Tail Storage",omega] == v[t-1,code,"PS Closed", "Tail Storage", omega] + q[t,code,"PS Closed",omega] - efficiency*d[t,code,"PS Closed",omega] )
               end

               # Properties of hydro:
               ## Units: Not modeled (Always assumed is 1)
               ## Max Capacity: Modeled if no rating is included (added as upper bound on q)
               ## Rating: Modeled (added as upper bound on q)
               ## Pump Load: Modeled (added as upper bound on d)
               ## Pump Efficiency: Modeled (added as efficiency on d)

               @constraint(model, q[t,code,"PS Closed",omega] <= rating_val)
               @constraint(model, q[t,code,"PS Closed",omega] >= min_load_val)
               @constraint(model, d[t,code,"PS Closed",omega] <= pump_load_val)

               #pump_load = get_vale(hydro[code]["PS Closed"]["Pump Load"], climatic_year, t)
               #@constraint(model, d[t,code,"PS Closed",omega] <= pump_load)
            end

            if "PS Open" in keys(hydro[code])

               if parametrization == true
                  natural_inflow_val = natural_inflow[t, code,"PS Open",omega]
                  initial_volume_head_val = initial_volume[code,"PS Open","Head Storage",omega]
                  initial_volume_tail_val = initial_volume[code,"PS Open","Tail Storage",omega]
                  rating_val = rating[t, code,"PS Open", omega]
                  min_load_val = min_load[t, code,"PS Open", omega]
                  pump_load_val = pump_load[t, code,"PS Open", omega]
               else
                  natural_inflow_val = hydro_storage[code]["PS Open"]["Head Storage"]["Natural Inflow"][climatic_year][t]
                  initial_volume_head_val = get_vale(hydro_storage[code]["PS Open"]["Head Storage"]["Initial Volume"], climatic_year, t)
                  initial_volume_tail_val = get_vale(hydro_storage[code]["PS Open"]["Tail Storage"]["Initial Volume"], climatic_year, t)

                  if "Rating" in keys(hydro[code]["PS Open"])
                     rating_val = get_vale(hydro[code]["PS Open"]["Rating"], climatic_year, t)
                  else
                     rating_val = hydro[code]["PS Open"]["Max Capacity"]
                  end

                  if "Min Load" in keys(hydro[code]["PS Open"])
                     min_load_val = get_vale(hydro[code]["PS Open"]["Min Load"], climatic_year, t)
                  else
                     min_load_val = 0.0
                  end

                  pump_load_val = get_vale(hydro[code]["PS Open"]["Pump Load"], climatic_year, t)
               end

               # Properties of hydro_storage:
               # Head Storage:
               ## End Effects Method: Not modeled
               ## Target penalty: Not modeled
               ## Target Year: Not modeled (the data is assumed to load the target year)
               ## Max Volume: Modeled (added as upper constraint on v, multiplied by 1000 to go GW to MW)
               ## Initial Volume: Modeled (added as initial condition on v, multiplied by 1000 to go GWh to MWh)
               ## Spill Penalty: Modeled (Penalized in the objective, divided by 1000 to go from $/GWh to $/MWh)
               ## Natrual Inflow: Modeled (added as energy that arrivees to the reservoir)

               efficiency = hydro[code]["PS Open"]["Pump Efficiency"]/100

               if t == 1
                  @constraint(model, v[t,code,"PS Open","Head Storage",omega] == initial_volume_head_val*1000/Duration[code][t] + natural_inflow_val + efficiency*d[t,code,"PS Open",omega] - q[t,code,"PS Open",omega] - s[t,code,"PS Open",omega])
               else
                  @constraint(model, v[t,code,"PS Open","Head Storage",omega] == v[t-1,code,"PS Open", "Head Storage", omega] + natural_inflow_val + efficiency*d[t,code,"PS Open",omega] - q[t,code,"PS Open",omega] - s[t,code,"PS Open",omega])
               end

               @constraint(model, v[t,code,"PS Open","Head Storage",omega] <= hydro_storage[code]["PS Open"]["Head Storage"]["Max Volume"]*1000)

               # Tail Storage:
               ## End Effects Method: Not modeled
               ## Initial Volume: Modeled (added as initial condition on v, multiplied by 1000 to go GWh to MWh)

               if t == 1
                  @constraint(model, v[t,code,"PS Open","Tail Storage",omega] == initial_volume_tail_val*1000/Duration[code][t] + q[t,code,"PS Open",omega] - efficiency*d[t,code,"PS Open",omega] )
               else
                 @constraint(model, v[t,code,"PS Open","Tail Storage",omega] == v[t-1,code,"PS Open", "Tail Storage", omega] + q[t,code,"PS Open",omega] - efficiency*d[t,code,"PS Open",omega] )
               end

               # Properties of hydro:
               ## Units: Not modeled (Always assumed is 1)
               ## Max Capacity: Modeled if no rating is included (added as upper bound on q)
               ## Rating: Modeled (added as upper bound on q)
               ## Pump Load: Modeled (added as upper bound on d)
               ## Pump Efficiency: Modeled (added as efficiency on d)

               @constraint(model, q[t,code,"PS Open",omega] <= rating_val)
               @constraint(model, q[t,code,"PS Open",omega] >= min_load_val)
               @constraint(model, d[t,code,"PS Open",omega] <= pump_load_val)
            end
         end
      end
   end
end

function add_batteries_constraints!(model::Model, NOmegas::Int64)
   bc = model[:bc]
   bd = model[:bd]
   bv = model[:bv]

   ################################
   ###### Battery Modeling
   for omega = 1:NOmegas
      for code in Codes
         for t in 1:T
            if "Battery" in keys(battery[code])
               initial_soc_val = battery[code]["Battery"]["Initial SoC"]
               charge_efficiency_val = battery[code]["Battery"]["Charge Efficiency"]
               capacity_val = battery[code]["Battery"]["Capacity"]
               max_power_val = battery[code]["Battery"]["Max Power"]

               # Properties of battery:
               # Battery:
               ## Units: Not modeled (assumed to be 1)
               ## Initial SoC: Modeled (used as inital charge on the battery, divided by 100)
               ## Charge Efficiency: Modeled (used to model the dynamic of the battery, divided by 100)
               ## Capacity: Modeled (used as upper bound on battery storage)
               ## Max Power: Modeled (used as upper bound on battery charge)
               ## Max Load ?: there is no max load, PLEXOS default value is 0 (used as upper bound on battery discharge)

               if t == 1
                  @constraint(model, bv[t,code,"Battery",omega] == (initial_soc_val/100)*capacity_val + (charge_efficiency_val/100)*bc[t,code,"Battery",omega] - bd[t,code,"Battery",omega])
               else
                  @constraint(model, bv[t,code,"Battery",omega] == bv[t-1,code,"Battery",omega] + (charge_efficiency_val/100)*bc[t,code,"Battery",omega] - bd[t,code,"Battery",omega])
               end
               @constraint(model, bv[t,code,"Battery",omega] <= capacity_val)
               @constraint(model, bc[t,code,"Battery",omega] <= max_power_val)
               @constraint(model, bd[t,code,"Battery",omega] <= max_power_val)
            end
         end
      end
   end
end

function add_load_balance_constraint!(model::Model, NOmegas::Int64)
   p = model[:p] # Existing generation units
   p_new = model[:p_new] # New Generating units
   p_DSR = model[:p_DSR]  # DSR
   ls = model[:ls] # load shedding
   ps = model[:ps] # production shedding
   q = model[:q] # Produced Hydro
   d = model[:d] # pumped hydro
   bd = model[:bd] # battery discharge
   bc = model[:bc] # battery charge

   fAC_p = model[:fAC_p] # lines AC positive part
   fAC_n = model[:fAC_n] # lines AC negative part

   fDC_p = model[:fDC_p] # lines DC positive part
   fDC_n = model[:fDC_n] # lines DC negative part

   ParamLoad = model[:ParamLoad]
   ParamDemand = model[:ParamDemand]

   for omega in 1:NOmegas
      for code in Codes
         for t in 1:T
            # Supply power
            power_supply = @expression(model,
            sum(p[t,code,g,omega] for g in Generator_category_node[code]) # Production current generators
            + sum(p_DSR[t,code,n,omega] for n in keys(DSR[code])) # Production DSR
            + sum(q[t,code,g,omega] for g in keys(hydro[code]) ) # Hydro
            + sum(bd[t,code,g,omega] for g in keys(battery[code]) ) # Battery dicharge
            + other_res_nores[code]["Others renewable"]["Max Capacity"] # Others renewable
            + other_res_nores[code]["Others non-renewable"]["Max Capacity"]  # Others non-renewable
            - ps[t,code,omega] # Production shedding
            + ls[t,code,omega] # Load shedding
            + sum(fAC_p[t,fromCode,code,n,omega] for fromCode in keys(LinesTo["HVAC"][code]), n in LinesTo["HVAC"][code][fromCode]) # AC positive part lines arriving leaving node
            - sum(fAC_n[t,fromCode,code,n,omega] for fromCode in keys(LinesTo["HVAC"][code]), n in LinesTo["HVAC"][code][fromCode]) # AC negative part lines arriving leaving node
            + sum(fDC_p[t,fromCode,code,n,omega] for fromCode in keys(LinesTo["HVDC"][code]), n in LinesTo["HVDC"][code][fromCode]) # DC positive part lines arriving leaving node
            - sum(fDC_n[t,fromCode,code,n,omega] for fromCode in keys(LinesTo["HVDC"][code]), n in LinesTo["HVDC"][code][fromCode]) # DC negative part lines arriving leaving node
            )

            if code in ExpantionCodes
               power_supply_expansion = @expression(model, sum(p_new[t,code,g,omega] for g in keys(Generators["New"][code])) ) # Production new generators
            else
               power_supply_expansion = @expression(model, 0) # Production new generators
            end

            # Demand power
            @constraint(model,
            power_supply + power_supply_expansion == ParamLoad[t,code,omega]
            + sum(d[t,code,g,omega] for g in intersect(keys(hydro[code]), ["PS Closed", "PS Open"]) ) # Pumped hydro
            + sum(bc[t,code,g,omega] for g in keys(battery[code]) ) # Battery charge
            + sum(fAC_p[t,code,toCode,n,omega] for toCode in keys(LinesFrom["HVAC"][code]), n in LinesFrom["HVAC"][code][toCode]) # AC positive part lines arriving leaving node
            - sum(fAC_n[t,code,toCode,n,omega] for toCode in keys(LinesFrom["HVAC"][code]), n in LinesFrom["HVAC"][code][toCode]) # AC negative part lines arriving leaving node
            + sum(fDC_p[t,code,toCode,n,omega] for toCode in keys(LinesFrom["HVDC"][code]), n in LinesFrom["HVDC"][code][toCode]) # DC positive part Lines arriving leaving node
            - sum(fDC_n[t,code,toCode,n,omega] for toCode in keys(LinesFrom["HVDC"][code]), n in LinesFrom["HVDC"][code][toCode]) # DC negative part lines arriving leaving node
            )

            # load shedding bound
            @constraint(model, ls[t,code,omega] <= ParamDemand[t,code,omega])
         end
      end
   end
end

function add_generator_constraints!(model::Model, NOmegas::Int64)
   x = model[:x] # first stage
   p = model[:p] # Existing generation units
   p_new = model[:p_new] # New Generating units
   p_DSR = model[:p_DSR]  # DSR

   for omega in 1:NOmegas
      ###########################################
      ###### Maximum & Minimum power generation

      # Existing generators
      for code in Codes
         for g in Generator_category_node[code]
            cap = Generators["Exist"][code][g]["Rating"]
            mincap = Generators["Exist"][code][g]["Min Load"]

            for t in 1:T
               @constraint(model, p[t,code,g,omega] >= mincap[t])
            end

            if g in generators_type["Retire"][code]
               for t in 1:T
                  max_cap = Generators["Exist"][code][g]["Retire capacity"]
                  cap_fraction = cap[t]/max_cap
                  @constraint(model, p[t,code,g,omega] <= cap_fraction*(max_cap-x["Retire",code,g]))
               end
            else
               for t in 1:T
                  @constraint(model, p[t,code,g,omega] <= cap[t])
               end
            end
         end
      end

      # New generators
      for code in ExpantionCodes
         for g in keys(Generators["New"][code])
            for t in 1:T
               @constraint(model, p_new[t,code,g,omega] <= x["Invest",code,g])
            end
         end
      end

      # DSR
      for code in Codes
         for n in keys(DSR[code])
            cap = DSR[code][n]["Offer Quantity"]

            for t in 1:T
               @constraint(model, p_DSR[t,code,n,omega] <= cap[t])
            end
         end
      end
   end
end

function add_lines_constraints!(model::Model, NOmegas::Int64)
   fAC_p = model[:fAC_p] # lines AC positive part
   fAC_n = model[:fAC_n] # lines AC negative part

   fDC_p = model[:fDC_p] # lines DC positive part
   fDC_n = model[:fDC_n] # lines DC negative part

   for omega in 1:NOmegas
      ################################
      ###### Maximum & Minimum NTC

      for code in Codes
         for toCode in keys(LinesFrom["HVAC"][code])
            for n in LinesFrom["HVAC"][code][toCode]
               cap = Lines["HVAC"][code][toCode][n]["Max Flow"]
               mincap = Lines["HVAC"][code][toCode][n]["Min Flow"]

               for t in 1:T
                  @constraint(model, fAC_p[t,code,toCode,n,omega] <= cap[t])
                  @constraint(model, fAC_n[t,code,toCode,n,omega] <= abs(mincap[t]))
               end
            end
         end

         for toCode in keys(LinesFrom["HVDC"][code])
            for n in LinesFrom["HVDC"][code][toCode]
               cap = Lines["HVDC"][code][toCode][n]["Max Flow"]
               mincap = Lines["HVDC"][code][toCode][n]["Min Flow"]

               for t in 1:T
                  @constraint(model, fDC_p[t,code,toCode,n,omega] <= cap[t])
                  @constraint(model, fDC_n[t,code,toCode,n,omega] <= abs(mincap[t]))
               end
            end
         end
      end
   end
end

################################
###### Gneral constraints

function add_reliability_constraints!(model::Model, NOmegas::Int64)
   inls = model[:inls] # Indicator variable of ls
   ls = model[:ls] # load shedding

   ################################
   ###### Realibility

   for code in reliability_nodes
      @constraint(model, sum(inls[t,code,omega]*Duration[code][t]*Probabilities[omega] for t in Allowed_ls, omega in 1:NOmegas) <= reliability_value)
   end

   for omega in 1:NOmegas
      for code in reliability_nodes
         for t in setdiff(1:T, Allowed_ls)
            @constraint(model, ls[t,code,omega] == 0)
            @constraint(model, inls[t,code,omega] == 0)
         end
         for t in Allowed_ls
            @constraint(model, ls[t,code,omega] - inls[t,code,omega]*PeakLoad[code][t] <= 0)
         end
      end
   end
end

############################################
#### Parameterization
############################################

function set_parametrization_values!(model::Model, scenarios)
   NOmegas = length(scenarios)
   ParamLoad = model[:ParamLoad]
   ParamDemand = model[:ParamDemand]

   natural_inflow = model[:natural_inflow]
   initial_volume = model[:initial_volume]
   rating = model[:rating]
   min_load = model[:min_load]
   pump_load = model[:pump_load]

   for scenario in 1:NOmegas
      omega = scenarios[scenario][2]
      climatic_year = climate_years["Names"][omega]

      for code in Codes
         hydro_storage_code = hydro_storage[code]
         hydro_code = hydro[code]
         for t in 1:T
            set_value(ParamLoad[t,code,scenario], ParsedLoad[code][t, omega])
            set_value(ParamDemand[t,code,scenario], block_demand[code][t, omega])

            if "Run-of-River" in keys(hydro_code)
               nat_inlfow = hydro_storage_code["Run-of-River"]["Head Storage"]["Natural Inflow"][climatic_year][t]
               fix(natural_inflow[t,code,"Run-of-River",scenario], nat_inlfow; force=true)
            end

            if "Reservoir" in keys(hydro_code)
               natural_inflow_val = hydro_storage_code["Reservoir"]["Head Storage"]["Natural Inflow"][climatic_year][t]
               fix(natural_inflow[t,code,"Reservoir",scenario], natural_inflow_val; force=true)

               if t == 1
                  initial_volume_val = get_vale(hydro_storage[code]["Reservoir"]["Head Storage"]["Initial Volume"], climatic_year, t)
                  fix(initial_volume[code,"Reservoir","Head Storage",scenario], initial_volume_val; force=true)
               end

               if "Rating" in keys(hydro[code]["Reservoir"])
                  rating_val = get_vale(hydro[code]["Reservoir"]["Rating"], climatic_year, t)
               else
                  rating_val = hydro[code]["Reservoir"]["Max Capacity"]
               end
               fix(rating[t,code,"Reservoir",scenario], rating_val; force=true)

               if "Min Load" in keys(hydro[code]["Reservoir"])
                  min_load_val = get_vale(hydro[code]["Reservoir"]["Min Load"], climatic_year, t)
               else
                  min_load_val = 0.0
               end
               fix(min_load[t,code,"Reservoir",scenario], min_load_val; force=true)
            end

            if "PS Closed" in keys(hydro_code)
               if t == 1
                  initial_volume_head_val = get_vale(hydro_storage[code]["PS Closed"]["Head Storage"]["Initial Volume"], climatic_year, t)
                  initial_volume_tail_val = get_vale(hydro_storage[code]["PS Closed"]["Tail Storage"]["Initial Volume"], climatic_year, t)

                  fix(initial_volume[code,"PS Closed","Head Storage",scenario], initial_volume_head_val; force=true)
                  fix(initial_volume[code,"PS Closed","Tail Storage",scenario], initial_volume_tail_val; force=true)
               end

               if "Rating" in keys(hydro[code]["PS Closed"])
                  rating_val = get_vale(hydro[code]["PS Closed"]["Rating"], climatic_year, t)
               else
                  rating_val = hydro[code]["PS Closed"]["Max Capacity"]
               end
               fix(rating[t,code,"PS Closed",scenario], rating_val; force=true)


               if "Min Load" in keys(hydro[code]["PS Closed"])
                  min_load_val = get_vale(hydro[code]["PS Closed"]["Min Load"], climatic_year, t)
               else
                  min_load_val = 0.0
               end
               fix(min_load[t,code,"PS Closed",scenario], min_load_val; force=true)

               pump_load_val = get_vale(hydro[code]["PS Closed"]["Pump Load"], climatic_year, t)
               fix(pump_load[t,code,"PS Closed",scenario], pump_load_val; force=true)
            end

            if "PS Open" in keys(hydro_code)
               natural_inflow_val = hydro_storage_code["PS Open"]["Head Storage"]["Natural Inflow"][climatic_year][t]
               fix(natural_inflow[t,code,"PS Open",scenario], natural_inflow_val; force=true)

               if t == 1
                  initial_volume_head_val = get_vale(hydro_storage[code]["PS Open"]["Head Storage"]["Initial Volume"], climatic_year, t)
                  initial_volume_tail_val = get_vale(hydro_storage[code]["PS Open"]["Tail Storage"]["Initial Volume"], climatic_year, t)

                  fix(initial_volume[code,"PS Open","Head Storage",scenario], initial_volume_head_val; force=true)
                  fix(initial_volume[code,"PS Open","Tail Storage",scenario], initial_volume_tail_val; force=true)
               end

               if "Rating" in keys(hydro[code]["PS Open"])
                  rating_val = get_vale(hydro[code]["PS Open"]["Rating"], climatic_year, t)
               else
                  rating_val = hydro[code]["PS Open"]["Max Capacity"]
               end
               fix(rating[t,code,"PS Open",scenario], rating_val; force=true)


               if "Min Load" in keys(hydro[code]["PS Open"])
                  min_load_val = get_vale(hydro[code]["PS Open"]["Min Load"], climatic_year, t)
               else
                  min_load_val = 0.0
               end
               fix(min_load[t,code,"PS Open",scenario], min_load_val; force=true)

               pump_load_val = get_vale(hydro[code]["PS Open"]["Pump Load"], climatic_year, t)
               fix(pump_load[t,code,"PS Open",scenario], pump_load_val; force=true)
            end
         end
      end
   end
end

function set_parametrization_values_expeted_values!(model::Model)
   ParamLoad = model[:ParamLoad]
   ParamDemand = model[:ParamDemand]
   ParamDemand = model[:ParamDemand]

   natural_inflow = model[:natural_inflow]
   initial_volume = model[:initial_volume]
   rating = model[:rating]
   min_load = model[:min_load]
   pump_load = model[:pump_load]

   for code in Codes
      hydro_storage_code = hydro_storage[code]
      hydro_code = hydro[code]
      for t in 1:T
         param_load_val = 0.0
         param_demand_val = 0.0

         for omega in 1:length(climate_years["Names"])
            param_load_val += ParsedLoad[code][t, omega]/length(climate_years["Names"])
            param_demand_val += block_demand[code][t, omega]/length(climate_years["Names"])
         end
         set_value(ParamLoad[t,code], param_load_val)
         set_value(ParamDemand[t,code], param_demand_val)

         if "Run-of-River" in keys(hydro_code)
            nat_inlfow = average_parameter(climate_years, hydro_storage_code["Run-of-River"]["Head Storage"]["Natural Inflow"], t)
            fix(natural_inflow[t,code,"Run-of-River",1], nat_inlfow; force=true)
         end

         if "Reservoir" in keys(hydro_code)
            natural_inflow_val = average_parameter(climate_years, hydro_storage_code["Reservoir"]["Head Storage"]["Natural Inflow"], t)
            fix(natural_inflow[t,code,"Reservoir",1], natural_inflow_val; force=true)

            if t == 1
               initial_volume_val = average_parameter(climate_years, hydro_storage[code]["Reservoir"]["Head Storage"]["Initial Volume"], t)
               fix(initial_volume[code,"Reservoir","Head Storage",1], initial_volume_val; force=true)
            end

            if "Rating" in keys(hydro[code]["Reservoir"])
               rating_val = average_parameter(climate_years, hydro[code]["Reservoir"]["Rating"], t)
            else
               rating_val = hydro[code]["Reservoir"]["Max Capacity"]
            end
            fix(rating[t,code,"Reservoir",1], rating_val; force=true)

            if "Min Load" in keys(hydro[code]["Reservoir"])
               min_load_val = average_parameter(climate_years, hydro[code]["Reservoir"]["Min Load"], t)
            else
               min_load_val = 0.0
            end
            fix(min_load[t,code,"Reservoir",1], min_load_val; force=true)
         end

         if "PS Closed" in keys(hydro_code)
            if t == 1
               initial_volume_head_val = average_parameter(climate_years, hydro_storage[code]["PS Closed"]["Head Storage"]["Initial Volume"], t)
               initial_volume_tail_val = average_parameter(climate_years, hydro_storage[code]["PS Closed"]["Tail Storage"]["Initial Volume"], t)

               fix(initial_volume[code,"PS Closed","Head Storage",1], initial_volume_head_val; force=true)
               fix(initial_volume[code,"PS Closed","Tail Storage",1], initial_volume_tail_val; force=true)
            end

            if "Rating" in keys(hydro[code]["PS Closed"])
               rating_val = average_parameter(climate_years, hydro[code]["PS Closed"]["Rating"], t)
            else
               rating_val = hydro[code]["PS Closed"]["Max Capacity"]
            end
            fix(rating[t,code,"PS Closed",1], rating_val; force=true)


            if "Min Load" in keys(hydro[code]["PS Closed"])
               min_load_val = average_parameter(climate_years, hydro[code]["PS Closed"]["Min Load"], t)
            else
               min_load_val = 0.0
            end
            fix(min_load[t,code,"PS Closed",1], min_load_val; force=true)

            pump_load_val = average_parameter(climate_years, hydro[code]["PS Closed"]["Pump Load"], t)
            fix(pump_load[t,code,"PS Closed",1], pump_load_val; force=true)
         end

         if "PS Open" in keys(hydro_code)
            natural_inflow_val = average_parameter(climate_years, hydro_storage_code["PS Open"]["Head Storage"]["Natural Inflow"], t)
            fix(natural_inflow[t,code,"PS Open",1], natural_inflow_val; force=true)

            if t == 1
               initial_volume_head_val = average_parameter(climate_years, hydro_storage[code]["PS Open"]["Head Storage"]["Initial Volume"], t)
               initial_volume_tail_val = average_parameter(climate_years, hydro_storage[code]["PS Open"]["Tail Storage"]["Initial Volume"], t)

               fix(initial_volume[code,"PS Open","Head Storage",1], initial_volume_head_val; force=true)
               fix(initial_volume[code,"PS Open","Tail Storage",1], initial_volume_tail_val; force=true)
            end

            if "Rating" in keys(hydro[code]["PS Open"])
               rating_val = average_parameter(climate_years, hydro[code]["PS Open"]["Rating"], t)
            else
               rating_val = hydro[code]["PS Open"]["Max Capacity"]
            end
            fix(rating[t,code,"PS Open",1], rating_val; force=true)


            if "Min Load" in keys(hydro[code]["PS Open"])
               min_load_val = average_parameter(climate_years, hydro[code]["PS Open"]["Min Load"], t)
            else
               min_load_val = 0.0
            end
            fix(min_load[t,code,"PS Open",1], min_load_val; force=true)

            pump_load_val = average_parameter(climate_years, hydro[code]["PS Open"]["Pump Load"], t)
            fix(pump_load[t,code,"PS Open",1], pump_load_val; force=true)
         end
      end
   end
end

function average_parameter(climate_years, data,t)
   val = 0.0
   for climatic_year in climate_years["Names"]
      curr_data = get_vale(data, climatic_year, t)
      val += curr_data/length(climate_years["Names"])
   end
   return val
end
