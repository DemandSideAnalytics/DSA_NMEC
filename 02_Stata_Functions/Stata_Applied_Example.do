
/*=============================================================================*

	Project: 	PG&E Residential Pay for Performance - 2022 Claimable Savings
	Date:		December 2022
	Written by: Adriana Ciccone
	Updated 2023 by: Davis Farr
	
	Purpose:	Import and clean the EE participation and customer 
				characteristics files
	
	
	Steps: 		1.	Import and clean the customer characteristics
					* Add weather station
					* Construct exclusion/characteristics variables
				2. 	Import and clean the participation information
					* Add ineligibility flags
		
*=============================================================================*/

	* Base Stata Settings
	version 16.0
	set scheme dsa, perm
	set more off, perm
	set autotabgraphs on, perm
	set seed 11235813
		
	cd  "D:/Projects/PG&E/2023-2025 OBF P4P NMEC Payable Savings"
	
	* load the functions
	do "Deliverables\05_Open_Source_Functions\02_Stata_Functions/dsa_temperature_bin.ado"
	do "Deliverables\05_Open_Source_Functions\02_Stata_Functions/dsa_seasonal_towt.ado"
	do "Deliverables\05_Open_Source_Functions\02_Stata_Functions/dsa_seasonal_dowt.ado"
	
/*=============================================================================*
	01. 	Run Savings on Hourly Data
*=============================================================================*/

*A. Load the prepared analysis data
	insheet using "Deliverables/05_Open_Source_Functions/01_Example_Data/Example_Hourly_Data.csv", comma clear
	
	* Process dates
	ren date strdate	
	gen date = date(strdate, "MDY")
	drop strdate			

	*B. Run the hourly model	
	dsa_seasonal_towt kwh tempf, id(premise) date(date) hour(hour)			///
		treatment(treatment) profiles(gp_*)  keepknots 
	
*C. Plot results	
	collapse (mean) kwh _counterfactual, by(date treatment premise)
	
	levelsof premise, local(prems)
	foreach p of local prems {
		twoway (line kwh _counterfactual date) if premise == `p',		///
			by(treatment, xrescale note("")) name(g_`p', replace)
	}	
	
/*=============================================================================*
	02. 	Run Savings on Daily Data
*=============================================================================*/

*A. Load the prepared analysis data
	insheet using "Deliverables/05_Open_Source_Functions/01_Example_Data/Example_Daily_Data.csv", comma clear
	
	* Process dates
	ren date strdate	
	gen date = date(strdate, "MDY")
	drop strdate			
			
*B. Run the hourly model	
	dsa_seasonal_dowt kwh tempf, id(premise) date(date) treatment(treatment) profiles(gp_*) 
	
*C. Plot results		
	levelsof premise, local(prems)
	foreach p of local prems {
		twoway (line kwh _counterfactual date) if premise == `p',		///
			by(treatment, xrescale note("")) name(g_`p', replace)
	}	
	
