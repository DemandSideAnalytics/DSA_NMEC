
cap program drop dsa_seasonal_towt
version 16.0
program dsa_seasonal_towt, rclass

/*
	Purpose: 	Computes a seasonal Time-of-Week & Temperature (TOWT) model
				with an optional synthetic control. The included variables
				are a 7-bin temperature spline, 168 hour-of-week dummy 
				variables and any optional granular profiles. Regressions are
				run independently for each season: Summer, Winter, and Shoulder.
		
	Assumed structure:
		data long by id(s) date hour
		id(s) | date | hour | treatment| temperature | profiles
		
	Required inputs:
		varlist: 		usage and temperature variables (must be in that order)
			
		[if]: 			optionally specified
		
		id: 			any combination of string and numeric unique identifiers 
		date: 			the date variable
		hour: 			the hour variable
		treatment: 		the treatment bool. Should be 0 for year of pretreat,
						1 for post-treat and missing for blackout periods or
						data prior to the baseline period
		
	Optional variables:
		profiles:		varlist of any other numeric variables to include in
						the regression. Note that factor and time-series 
						variables are not allowed. This is implemented as a 
						varlist, so stata wildcard such as * are allowed. 
		sterloc:		path to a location to save STER files of the regression
						outputs. Saves 3 STER files for each site (assuming)
						data coverage 1=summer, 2=winter, 3=shoulder. IDs
						are passed as strings of the ID varlist in to the 
						file name. Note that it works best if you have one
						short ID rather than multiple long strings
		sterreplace		Flag allowing you to overwrite the existing STER if 
						it exists. If you do not populate this, the analysis
						will complete but the STER file will not be saved
		keepknots		Keep the values of the spline knot lower and upper
						bins as well as flags for valid bins.
						
	Outputs:
		returns the input dataset with the following additional variables:
		_analysis:		a binary flag for whether the observation was included
						in the regression or post-treatment counterfactual
						generation. 
		_season:		the season of the month. 1 = summer, 2 = winter, and
						3 = shoulder
		_month:			month 1-12
		_training: 		binary flag for the year of pre-treatment
		_post: 			binary flag for the post-treatment period
		_counterfactual:the counterfactual usage. We predict for all obs, not
						just in the post period
		_b*_lb			Lower bound of temperature bins if keepknots specified
		_b*_ub			Upper bound of temperature bins if keepknots specified
		_b*_valid		If bin is valid (if keepknots specified)
		_high_bin		The highest valid bin (if keepknots specified)
*/
		
	
	
*A. Define the syntax
syntax varlist(min=2 max=2) [if], id(varlist) date(varlist) hour(varlist) 	///
		treatment(varlist numeric) [profiles(varlist numeric) 				///
		sterloc(string) sterreplace keepknots]
	
	* Make the saving file location if it doesn't already exist
	if "`sterloc'" != "" {
		cap mkdir "`sterloc'"
	}
				
*B. Save original dataset (tempfile)
	qui {
	
	tempfile original
	save `original'

	marksample touse
	keep if `touse'
	
*C. Validation of syntax inputs
	tokenize 	`varlist'
	local 		usage `1'
	local		tempf `2'
		
*D. Keep the relevant variables only 
	keep `id' `date' `hour' `usage' `tempf' `treatment' `profiles'

*E. Incorporate catch for multiple id values
	egen _chid = group(`id'), label lname("_chid")
	sum _chid
	local _maxid = r(max)
		
*F. Create analysis variables and flag relevant buckets
	*01. create month variable
	gen _month 		= month(`date')
	gen _season 	= .
	replace _season = 1 if inrange(_month, 6, 9)	// summer
	replace _season = 2 if !inrange(_month, 4, 11)	// winter
	replace _season = 3 if _season == .	 			// shoulder?
	
	*02. create hour-dow variable (1-168) (Monday through Sunday)
	gen 	_dow 	= dow(`date')
	replace _dow 	= 7 if _dow == 0
	egen _tow 		= group(_dow `hour')
	
	*03. create post flag (blackout period and any data prior to a year before
	* 	installation is coded as treatment == .)
	gen _post		= `treatment' == 1
	gen _training 	= `treatment' == 0
			
*G. Set up monthly loop
	*01. Save Tempfile to use throughout development of analysis dataset
	tempfile analysis
	save `analysis'
		
	*02. Create empty dataset to append results to 
	clear
	tempfile results
	save `results', replace emptyok

	*04. Start Seasonal Loop
	forval s = 1/3 { 
				
		* Bring in the analysis data for only the valid months
		use if _season == `s' using `analysis', clear
		
		* we may not have all months available in post (so make sure to handle
		* missing months with captures) 
		capture {
        
		/*=============================================================*
			run temperature bin function
		*=============================================================*/
		
		* prep the results containers
		forval b = 1/7 {
		    gen _temp_bin_`b' 	= .
		}

		* run the temperature code
		dsa_temperature_bin `tempf' if _training == 1, id("_chid")
			
		tempfile _temperaturemerge
		save `_temperaturemerge', replace
		
		* load the temperature result
		clear
		svmat temp_bins, names(col)
		
		* Drop if all ids are blank (can happen if customer doesn't have data
		* for a given month)
		drop if _chid == .
		
		* merge the temperature result back to the main dataset
		merge 1:m _chid using `_temperaturemerge', nogen
		
		* construct temperature bins for pre and post flag highest valid bin 
		gen _high_bin = 1		
		forvalues b = 1/7 {
			replace _high_bin = `b' if _b`b'_valid == 1
		}

		* Loop through the bins and fill in the temperature bins	
		forval b = 1/7 {
			* Bin 1: we know it will always be either the temperature or  
			* the lower bound (when tempf is > lower bound)
			if `b' == 1 {
				replace _temp_bin_`b' = min(`tempf', _b`b'_ub)	
			}
			* Middle Bins: The smaller of the difference between the temp
			* and the lower bound OR the width of the bin (upper - lower)
			* If the temp < lower bound, value is 0
			if `b' > 1 {
				replace _temp_bin_`b' = 									///
					min(`tempf'-_b`b'_lb, _b`b'_ub-_b`b'_lb)				///
					if inrange(`b', 2, _high_bin - 1)			
				replace _temp_bin_`b' = 0 if `tempf' < _b`b'_lb
				
			* Highest Bin: The amount above the lower bound of the highest
			* bin (and 0 if the temperature is lower than the low bound)
				replace _temp_bin_`b' = max(`tempf'-_b`b'_lb, 0) 		///
					if `b' == _high_bin
			}
			
			* round the temperature bins & set so that the values or 0 not .
			replace _temp_bin_`b' = round(_temp_bin_`b', 0.01)
			replace _temp_bin_`b' = 0 if _temp_bin_`b' == .	
		}	
			
		/*=============================================================*
			regress using regression method on pre period
		*=============================================================*/
				
		gen _counterfactual = .
		gen _synthetic_ctrl = . 
		forval p = 1/`_maxid' {
			
			sum _high_bin if _chid == `p'
			local hb = r(max)
			local obs = r(obs)
			
			local idlabel: lab _chid `p'
			
			cap { 	// for cases where there is no data in that month for a
					// given customer
			
				* Run Regression
				reg `usage' ibn._tow  c._temp_bin_*	 `profiles' 		///
					if _training == 1 & _chid == `p', noconstant
						
				local sterreplaceval = ""
				if "`sterreplace'" != "" {
					local sterreplaceval = "replace"
				}
						
				if "`sterloc'" != "" {
					cap estimates save "`sterloc'/seasonal_towt_`idlabel'_s`s'.ster", `sterreplaceval'
					if _rc != 0 {
						noi di as error "Estimates unable to be saved for `idlabel' season `s'"
						noi di as error `"Results still produced. Check the "sterreplace" option for more details"'
					}
				}
									
				* predict
				predict _cf`p', xb
				
			}
		}
		
		* Keep values of interest & clean up 
		forval p = 1/`_maxid' {
			cap replace _counterfactual = _cf`p' if _chid == `p'
		}	
		
		local knots ""
		if "`keepknots'" != "" {
			local knots = "_b*_lb _b*_ub _b*_valid _high_bin" 
		}
		
		keep `id' `date' `hour' _season _month _training _post 	///
			_counterfactual `knots'

		* Append to the overall results file
		append using `results'
		save `results', replace
	
		} 	// end capture loop
	} 		// end month loop
	
	
*H. Merge the predicted results back to the original file
	use `original', clear	
	merge 1:1 `id' `date' `hour' using `results', nogen
	gen _analysis = _training == 1 | _post == 1
	
	
*I. Label the analysis variables
	label var _analysis 		"Seasonal TOWT: Training and Reporting Period"
	label var _training 		"Seasonal TOWT: Observations used to train the model"
	label var _post 			"Seasonal TOWT: Post-treatment period"
	label var _season 			"Seasonal TOWT: Season used for regression analysis"
	label var _month 			"Seasonal TOWT: Month"
	label var _counterfactual 	"Seasonal TOWT: Model Counterfactual"
			
	if "`keepknots'" != "" {
		forval b = 1/7 {
			label var _b`b'_lb		"Seasonal TOWT: Bin `b' Lower Bound"
			label var _b`b'_ub		"Seasonal TOWT: Bin `b' Upper Bound"
			label var _b`b'_valid	"Seasonal TOWT: Bin `b' Valid Bin"
		}
		label var _high_bin			"Seasonal TOWT: Highest Valid Temp Bin"
	}		
			
			
	label define _season 1 "Summer" 2 "Winter" 3 "Shoulder", modify
	label val _season _season
			
	}	// end quietly	
end