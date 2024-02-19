{smcl}
{hline}
help for {hi:dsa_seasonal_dowt}
{hline}

{title:Seasonal Day-of-Week & Temperature Regression}

{p 8 21 2}{cmdab:dsa_seasonal_dowt}
{varname} 
{varname}
[{cmd:if} {it:exp}]
{cmd:,}
	{cmdab:id}{cmd:(}{varlist}{cmd:)}
    {cmdab:date}{cmd:(}{varname}{cmd:)}
    {cmdab:treatment}{cmd:(}{varname}{cmd:)}
    [{cmdab:profiles}{cmd:(}{varlist}{cmd:)}
	{cmdab:sterloc}{cmd:(}{it:string}{cmd:)}
	{cmdab:sterreplace} {cmdab:keepknots}]


{title:Description}

{pstd}
{cmd:dsa_seasonal_dowt} Runs a simple day-of-week temperature OLS regression by site using daily consumption data. The user should specify the consumption variable as varname 1, the temperature variable (in Fahrenheit) as varname 2, and then pass site/customer IDs ({cmdab:id}), a date ({cmdab:date}) variables, and a treatment ({cmdab:treatment}) indicator variable as required options. The user can optionally include one or more granular profiles ({cmdab:profiles}) as a synthetic control. Finally, if the user desires to save the regression output, they can do so by specifiying the {cmdab:sterloc} which passes the directory path where files should be saved. 

The regressions are run independently by season: 
{pstd} {bf:summer}: {tab} June-September {p_end}
{pstd} {bf:winter}: {tab} December-March {p_end}
{pstd} {bf:shoulder}: {tab} All Other Months {p_end}

{pstd}
Input dataset must be specified with unique account or premise id(s) and date long by row, with a binary 0/1 treatment indicator variable. {p_end}

{title:Syntax}

{pstd}
DOWT Within Subjects Regression

{p 8 15 2}
{cmdab:dsa_seasonal_dowt} kwh tempf{cmd:,}
	{cmdab:id}{cmd:(}{varlist}{cmd:)}
    {cmdab:date}{cmd:(}{varname}{cmd:)}
	{cmdab:treatment}{cmd:(}{varname}{cmd:)}

{pstd}
DOWT with Synthetic Control

{p 8 15 2}
{cmdab:dsa_seasonal_dowt} kwh tempf{cmd:,}
	{cmdab:id}{cmd:(}{varlist}{cmd:)}
    {cmdab:date}{cmd:(}{varname}{cmd:)}
	{cmdab:treatment}{cmd:(}{varname}{cmd:)}
	{cmdab:profiles}{cmd:(}{varlist}{cmd:)}

	
{pstd}
DOWT Within Subjects with STER Saving

{p 8 15 2}
{cmdab:dsa_seasonal_dowt} kwh tempf{cmd:,}
	{cmdab:id}{cmd:(}{varlist}{cmd:)}
    {cmdab:date}{cmd:(}{varname}{cmd:)}
	{cmdab:treatment}{cmd:(}{varname}{cmd:)}
	{cmdab:sterloc}{cmd:(}string{cmd:)}

	
{pstd}
DOWT Within Subjects with STER Saving and STER Updating

{p 8 15 2}
{cmdab:dsa_seasonal_dowt} kwh tempf{cmd:,}
	{cmdab:id}{cmd:(}{varlist}{cmd:)}
    {cmdab:date}{cmd:(}{varname}{cmd:)}
	{cmdab:treatment}{cmd:(}{varname}{cmd:)}
	{cmdab:sterloc}{cmd:(}string{cmd:) {cmdab:sterreplace}}	

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{syntab :Required}
{synopt :{opth id(varlist)}}List of ID variables that indicate a unique observation; typically an account or premise {p_end}
{synopt :{opth date(varname)}}The numeric variable representing the date{p_end}
{synopt :{opth treatment(varname)}}The numeric variable representing the treatment indicator. Must be 0 for pre-treatment to be included in the regression, 1 for post treatment, and missing for any blackout or exclusion periods{p_end}

{syntab :Options}
{synopt :{opth profiles(varlist)}}One or more numeric variables that can act as a synthetic controls{p_end}
{synopt :{opth sterloc(string)}}Sets the path to save the STER files for each site. Accepts Stata global and local macros{p_end}
{synopt :{bf:sterreplace}}Allows overwriting of the STER file if it already exists. If the STER file already exists and this option is not called, the regression will still be run but no STER file will be saved{p_end}
{synopt :{bf:keepknots}}Keeps the lower and upper bounds of the pruned temperature spline in the final returned dataset{p_end}

{title:Requirements}
{pstd}
{cmd:dsa_seasonal_dowt} requires {cmd:dsa_temperature_bin} 



{dlgtab:Results}

{phang}
{cmd:dsa_seasonal_dowt} returns the original dataset with additional variables: {p_end}

{phang} {bf:_analysis}: A binary flag for whether the observation was included in as part of the training/baseline or post-treatment period. Missing for all other observations{p_end}
{phang} {bf:_season}: The season of each month. 1 = summer, 2 = winter and 3 = shoulder {p_end}
{phang} {bf:_training}: Binary flag indicating whether the observation was part of the training/baseline period {p_end}
{phang} {bf:_post}: Binary indicator for whether the observation was part of the post-treatment period {p_end}
{phang} {bf:_month}: Month 1-12 of the observation {p_end}
{phang} {bf:_counterfactual}: the counterfactual usage. We predict for all observations, not just in the post period {p_end}
{phang} {bf:_b*_lb}: If {cmdab:keepknots} specified. Returns the lower bound of the temperature spline for bin.{p_end}
{phang} {bf:_b*_ub}: If {cmdab:keepknots} specified. Returns the upper bound of the temperature spline for bin.{p_end}
{phang} {bf:_b*_valid}: If {cmdab:keepknots} specified. Binary flag 0/1 for whether this bin is valid bin for the temperature spline.{p_end}
{phang} {bf:_high_bin}: If {cmdab:keepknots} specified. The highest valid bin of the temperature spline.{p_end}



{title:Author}

{pstd}
Adriana Ciccone, Demand Side Analytics, LLC. For questions, contact {browse "mailto:aciccone@demandsideanalytics.com"}

