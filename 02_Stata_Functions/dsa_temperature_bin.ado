	
version 16.0
program dsa_temperature_bin, rclass

/*
	Purpose: Computes the valid customer-specific temperature bins
		
	Assumed structure:
		data long by id(s) date hour
		id(s) | date | hour | temperature
		
	Required inputs:
		varlist: temperature variable. Temperature must be in Fahrenheit
			
		[if]: 	optionally specified
		id: 	any combination of string and numeric unique identifiers 
						
	Outputs:
		a matrix called temp_bins that is long by id(s) wide by 
		bins 1-7 valid, lower bound, and upper bound 
			
		For non valid bins, lower bound and upper bound are missing. For the
		first (lowest) valid bin, lower bound is missing. For the last (highest)
		valid bin, the upper bound is missing.  
*/
	
syntax varlist(min=1 max=1) [if], id(string) [DIAGNOSTIC]
	
	qui {
		
*A. Save the original file in case of errors
	tempfile original
	save `original', replace	
	
	* drop any existing matrices
	matrix drop _all
	
*B. Validate syntax
	tokenize `varlist'
	local tempf `1'	
	
*C. Keep relevant variables	
	marksample touse
	keep if `touse'

	keep `id' `tempf' 
	egen _tbid = group(`id')

*D. Generate the baseline temperature bins
	gen _count_1 = `tempf' <= 30
	gen _count_2 = `tempf' > 30 & `tempf' <= 45
	gen _count_3 = `tempf' > 45 & `tempf' <= 55
	gen _count_4 = `tempf' > 55 & `tempf' <= 65
	gen _count_5 = `tempf' > 65 & `tempf' <= 75
	gen _count_6 = `tempf' > 75 & `tempf' <= 90
	gen _count_7 = `tempf' > 90

	drop if `tempf' == .
	
	
	collapse (sum) _count_*, by(_tbid `id')
	reshape long _count_, i(_tbid `id') j(_bin)

*E. Add in the bin specifications
	gen _lb = .
	gen _ub = .
	
	replace _lb = -9999		if _bin == 1
	replace _lb = 30.00001 	if _bin == 2
	replace _lb = 45.00001 	if _bin == 3
	replace _lb = 55.00001 	if _bin == 4
	replace _lb = 65.00001 	if _bin == 5
	replace _lb = 75.00001 	if _bin == 6
	replace _lb = 90.00001 	if _bin == 7
	
	replace _ub = 30 		if _bin == 1
	replace _ub = 45 		if _bin == 2
	replace _ub = 55 		if _bin == 3
	replace _ub = 65 		if _bin == 4
	replace _ub = 75 		if _bin == 5
	replace _ub = 90 		if _bin == 6
	replace _ub = 9999 		if _bin == 7		

*F. Flag the bins requiring amalgamation
	gen _flag = 0	
		
	* Allocate upwards for bins that are less than 20 count
	gen _bad_up = 0
	qui forval b = 2(1)7 {
		bysort _tbid: 			replace _flag = _count_[`b' - 1] < 20
		bysort _tbid (_bin): 	replace _count_ = _count_ + _count_[`b' - 1] ///
												if _bin == `b' & _flag
		bysort _tbid (_bin): 	replace _bad_up = 1 if _bin == (`b' - 1) & _flag
		
		replace _count_ = 0 if _bad_up == 1
	}
	
	* Allocate downwards for bins that are less than 20 count
	gen _bad_dn = 0
	qui forval b = 6(-1)1 {
		bysort _tbid: 			replace _flag = _count_[`b' + 1] < 20
		bysort _tbid (_bin): 	replace _count_ = _count_ + _count_[`b' + 1] ///
												if _bin == `b' & _flag
		bysort _tbid (_bin): 	replace _bad_dn = 1 if _bin == (`b' + 1) & _flag
		
		replace _count_ = 0 if _bad_dn == 1
	}
	
	drop _flag
	
*G. Define the amalgamated groups & collapse to get new endpoints
	* Group the new bins together
	bysort _tbid (_bin): gen _newbin = _n if !(_bad_up | _bad_dn)
	gsort _tbid -_bin
	by _tbid: carryforward _newbin, replace
	gsort _tbid _bin
	by _tbid: carryforward _newbin, replace
	
	* Get the min/max edgepoints
	collapse (min) _lb (max) _ub (sum) _count_, by(_tbid `id' _newbin)

	* Recode the min/max so they are missing
	replace _lb = . if _lb == -9999
	replace _ub = . if _ub == 9999
	
	* Recode the bins so that they start at 1
	sort _tbid _newbin
	by _tbid: replace _newbin = _n 
	
	* Format 
	ren _newbin _bin
	sort _tbid _bin
	
	tempfile _matrixprep
	save `_matrixprep', replace
	
*H. Store results in a matrix
	* First ensure we have a full panel
	keep _tbid `id'
	duplicates drop
	expand 7 // temperature bins
	bysort _tbid: gen _bin = _n
	
	merge 1:1 _tbid _bin using `_matrixprep'
	gen _valid = _merge == 3
	
	* Keep the relevant data and reshape wide
	keep `id' _bin _valid _lb _ub
	reshape wide _valid _lb _ub, i(`id') j(_bin)
	
	* Get the results in names that the caltrack hourly code expects
	ren _valid* _b*_valid
	ren _lb* 	_b*_lb
	ren _ub*	_b*_ub
	
	* Store in a matrix
	mkmat `id' _b*_*, matrix(temp_bins)
	
	use `original', clear
	}	
	
end

		