{smcl}
{hline}
help for {hi:dsa_temperature_bin}
{hline}

{title:Dynamic Spline Temperature Bin Construction}

{p 8 21 2}{cmdab:dsa_temperature_bin}
{varname}
[{cmd:if} {it:exp}]
{cmd:,}{cmdab:id}{cmd:(}{varname}{cmd:)}


{title:Description}

{pstd}
{cmd:dsa_temperature_bin} Produces the cutpoints for dynamic spline bins by customer for temperatures in Fahrenheit, per the CalTRACK documentation: Caltrack V2.0 Section 3.9, viewable at http://docs.caltrack.org/en/latest/methods.html

{pstd}
Minimal validation is done on this data. It is assumed that you are passing in a dataset long by ID/date/hour, but the date and hour variables are immaterial to this computation and are not used. Temperature must be specified in Fahrenheit. Refer to the CalTRACK documentation for specifics on how the temperature bins are constructed. 
{p_end}

{title:Syntax}

{pstd}
Dynamic Spline

{p 8 15 2}
{cmdab:dsa_temperature_bin} tempf {cmd:,}
	{cmdab:id}{cmd:(}{varlist}{cmd:)}

{synoptset 20 tabbed}{...}
{synopthdr}
{synoptline}
{syntab :Required}
{synopt :{opth id(varlist)}}List of ID variables that indicate a unique observation; typically an account or premise {p_end}


{dlgtab:Results}

{phang}
{cmd:dsa_temperature_bin} returns a MATA matrix called temp_bins with the cutpoints specified by ID {p_end}


{title:Author}

{pstd}
Adriana Ciccone, Demand Side Analytics, LLC. For questions, contact {browse "mailto:aciccone@demandsideanalytics.com"}

