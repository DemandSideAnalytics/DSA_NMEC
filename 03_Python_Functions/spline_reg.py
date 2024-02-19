# -*- coding: utf-8 -*-
"""
Created on Thu Sep 29 10:38:42 2022

@author: aciccone
"""

#============================================================================#
#	01    Define the directories for testing and libraries for import
#============================================================================#

import numpy as np
import pandas as pd
import statsmodels.api as sm


pd.set_option('display.max_rows', 500)
pd.set_option('display.max_columns', 500)
pd.set_option('display.width', 1000)
pd.options.mode.chained_assignment = None  # default='warn'


basepath = "D:/Projects/PG&E/2023-2025 OBF P4P NMEC Payable Savings/"
dir2 = "Deliverables/05_Open_Source_Functions/01_Example_Data/"
analysis ="Example_Hourly_Data.csv"


'''
general disclaimers. only tested on one idvar
should work with hour 0-23, but tested on hour-ending 1-24

'''

#============================================================================#
#	02    Prep Data
#============================================================================#

def prep_data(df, splineargs):
    '''
    Takes the raw data and applies cleaning. Removes NAN/Nulls, collapses
    to a daily value if required by regression, and constructs the seasons
    needed for the seasonal regression

    Parameters
    ----------
    df : pandas dataframe
        data frame (no index) with the columns
    splineargs : dict
        regression parameters

    Returns
    -------
    df : pandas dataframe
        dataframe that has been cleaned with an additional variable '_season'
        based on the splinearg['seasons'] mapping of months to seasons

    '''

    # Parse the spline parameters
    idvar = splineargs['idvars']
    date = splineargs['date']
    hour = splineargs['hour']
    dailybool = splineargs['dailybool']
    seasons = splineargs['seasons']
    
    # Clean the data
    df[date] = pd.to_datetime(df[date], format="%m/%d/%Y")

    # Assign seasons to the data
    df['_season'] = df[date].dt.month.apply(str).map(seasons)

    # Remove any missing values
    df = df.dropna()

    # Check if daily and group mean by ID & date if so
    if dailybool:
        df = df.groupby([idvar, date]).mean()
        df = df.drop([hour], axis = 1)
    
    # Convert back to numeric index
    df = df.reset_index()
        
    return df



#============================================================================#
#	03    Construct Temperature Splines
#============================================================================#

def static_spline(df, splineargs):
    '''
    Constructs a temperature spline with fixed cutpoints

    Parameters
    ----------
    df : Pandas dataframe
        Dataframe that has the required temperature var for spline
        construction. Note that 'tempvar' must be a column in 'df'
    splineargs : dict
        regression parameters

    Returns
    -------
    df : Pandas dataframe with the spline variables added
    binlist : list of the column names in df that contain the spline vars

    '''
    
    # Validate that  tempvar exists in column
    tempvar = splineargs['tempvar']
    if tempvar not in df.columns:
        raise KeyError('{} not in dataframe'.format(tempvar))
        
    df['bin_0'] = np.minimum(50.0, df[tempvar])  
    df['bin_1'] = np.where(df[tempvar] >= 50.0, np.minimum(10.0, df[tempvar]-50.0), 0.0)
    df['bin_2'] = np.where(df[tempvar] >= 60.0, np.minimum(10.0, df[tempvar]-60.0), 0.0)
    df['bin_3'] = np.maximum(0.0, df[tempvar]-70.0)  
    
    binlist = ['bin_{}'.format(i) for i in range(4)]
    
    return df, binlist



def dsa_temperature_bin(df, splineargs):
    '''
    Using input data, constructs spline cutpoint values for each site
    dynamically, ensuring that each bin has sufficient temperature
    values for analysis.

    Parameters
    ----------
    df : Pandas dataframe
        Dataframe that has the required temperature var for spline
        construction. Note that 'tempvar' must be a column in 'df'. The 
        df may have one or more sites/idvar levels represented. 
    splineargs : dict
        regression parameters

    Returns
    -------
    df : Pandas dataframe with the spline variables added
    binlist : list of the column names in df that contain the spline vars

    '''
    
    # ========================================================================
    # Set up 
    
    # Parse the spline arguments reuired for the analysis
    temperature_var = splineargs['tempvar']
    id_var = splineargs['idvars']
    mincount = splineargs['mintempcount']
    

    # D. Generate the starting temperature bins
    bins = [float('-inf'), 30, 45, 55, 65, 75, 90, float('inf')]
    bin_labels = range(1, len(bins)) # range(1, len(bins) + 1) 
    

    df['_bin'] = pd.cut(df[temperature_var], bins=bins, labels=bin_labels, include_lowest=True)

    # Get the counts of temperature values in each original bin range
    df['_count_'] = 1
    df = df[[id_var, '_bin', '_count_']].groupby([id_var, '_bin']).sum().reset_index()

    # Make sure we have full bin coverage (fill in bins 0-7 for each site)
    fullbins = pd.DataFrame({'_bin': range(1, 8)})
    fullbins = df[[id_var]].drop_duplicates().merge(fullbins, how='cross')
    df = pd.merge(fullbins, df, how='outer', on=[id_var, '_bin'])
    
    # Add in the bin cutpoint specifications
    df['_lb'] = np.where((df['_bin'] == 1), float('-inf'), np.NAN)
    df['_lb'] = np.where((df['_bin'] == 2), 30.00001, df['_lb'])
    df['_lb'] = np.where((df['_bin'] == 3), 45.00001, df['_lb'])
    df['_lb'] = np.where((df['_bin'] == 4), 55.00001, df['_lb'])
    df['_lb'] = np.where((df['_bin'] == 5), 65.00001, df['_lb'])
    df['_lb'] = np.where((df['_bin'] == 6), 75.00001, df['_lb'])
    df['_lb'] = np.where((df['_bin'] == 7), 90.00001, df['_lb'])
    
    df['_ub'] = np.where((df['_bin'] == 1), 30, np.NAN)
    df['_ub'] = np.where((df['_bin'] == 2), 45, df['_ub'])
    df['_ub'] = np.where((df['_bin'] == 3), 55, df['_ub'])
    df['_ub'] = np.where((df['_bin'] == 4), 65, df['_ub'])
    df['_ub'] = np.where((df['_bin'] == 5), 75, df['_ub'])
    df['_ub'] = np.where((df['_bin'] == 6), 90, df['_ub'])
    df['_ub'] = np.where((df['_bin'] == 7), float('inf'), df['_ub'])

    # ========================================================================
    # Run the bin cutpoint pruning algorithm

    # Flag the bins requiring amalgamation
    df['_flag'] = 0
    df = df.sort_values([id_var, '_bin'])
        
    # Allocate upwards for bins that are less than 20 count
    df['_bad_up'] = 0
    for b in range(2, 8):
        df = df.sort_values([id_var, '_bin'])
        df['_flag'] = np.where((df[id_var] == df[id_var].shift(1)) & (df['_bin'] == b) & (df['_count_'].shift(1) < mincount), 1, 0)
        df['_count_'] = np.where((df[id_var] == df[id_var].shift(1)) & (df['_bin'] == b) & (df['_flag'] == 1), df['_count_'] + df['_count_'].shift(1), df['_count_'])
        df['_bad_up'] = np.where((df[id_var] == df[id_var].shift(-1)) & (df['_bin'] == (b-1)) & (df['_flag'].shift(-1) == 1), 1, df['_bad_up'])
        df['_count_'] = df['_count_'].where(df['_bad_up'] != 1, 0)
                
    # Allocate downwards for bins that are less than 20 count
    df['_bad_dn'] = 0
    for b in range(6, 0, -1):
        df['_flag'] = np.where((df[id_var] == df[id_var].shift(-1)) & (df['_bin'] == b) & (df['_count_'].shift(-1) < mincount), 1, 0)
        df['_count_'] = np.where((df[id_var] == df[id_var].shift(-1)) & (df['_bin'] == b) & (df['_flag'] == 1), df['_count_'] + df['_count_'].shift(-1), df['_count_'])
        df['_bad_dn'] = np.where((df[id_var] == df[id_var].shift(1)) & (df['_bin'] == (b+1)) & (df['_flag'].shift(1) == 1), 1, df['_bad_dn'])
        df['_count_'] = df['_count_'].where(df['_bad_dn'] != 1, 0)
        
    df.drop('_flag', axis=1, inplace=True)

    # Define the amalgamated groups & collapse to get new endpoints
    # Group the new bins together
    df['_newbin'] = df.sort_values(by=[id_var, '_bin']).groupby([id_var]).cumcount() + 1
    df['_newbin'] = df['_newbin'].where(~((df['_bad_up'] == 1) | (df['_bad_dn'] == 1)), None)

    # Sort the DataFrame
    df.sort_values(by=[id_var, '_bin'], ascending=[True, False], inplace=True)

    # Carry forward _newbin within each idvar
    df['_newbin'] = df.groupby(id_var)['_newbin'].ffill()

    # Sort the DataFrame again
    df.sort_values(by=[id_var, '_bin'], inplace=True)

    # Carry forward _newbin again within each idvar
    df['_newbin'] = df.groupby(id_var)['_newbin'].ffill()

    # Get the min/max edgepoints
    result_df = df.groupby([id_var, '_newbin']).agg(
        {'_lb':'min', '_ub':'max', '_count_':'sum'}).reset_index()

    # Recode the bins so that they start at 1
    result_df['_newbin'] = result_df.groupby(id_var).cumcount() + 1

    # ========================================================================
    # Clean the resulting dataset

    # Format
    result_df.rename(columns={'_newbin': '_bin'}, inplace=True)
    result_df.sort_values(by=[id_var, '_bin'], inplace=True)
    result_df['_maxbin'] = result_df.groupby(id_var)['_bin'].transform('max')

    # Make sure there is a full set of bins for each ID
    result_df = pd.merge(fullbins, result_df, how='outer', on=[id_var, '_bin'])

    # Fill in the results from the merge above
    result_df.sort_values(by=[id_var, '_bin'], inplace=True)
    result_df['_maxbin'] = result_df.groupby(id_var)['_maxbin'].ffill()
    
    # Reshape the DataFrame wide by 'bin' and keep it long by 'idvar'
    result_df = result_df.drop(columns='_count_')
    wide_df = result_df.pivot(index=[id_var, '_maxbin'], columns='_bin').sort_index(axis=1, level=1)
   
    # Flatten the MultiIndex columns
    wide_df.columns = [f'{col[0]}_{col[1]}' for col in wide_df.columns]

    return wide_df.reset_index()


def dynamic_spline(df, splineargs):
    '''
    Constructs a temperature spline with dynamic cutpoints allowing for
    sufficient data to be included in each temperature bin. Relies on
    temperature_bins() function to get the valid cutpoints

    Parameters
    ----------
    df : Pandas dataframe
        Dataframe that has the required temperature var for spline
        construction. Note that 'tempvar' must be a column in 'df'
    splineargs : dict
        regression parameters

    Returns
    -------
    df : Pandas dataframe with the spline variables added
    binlist : list of the column names in df that contain the spline vars

    '''    
        
    # call the temperature bins function to get bin cutpoints
    tempvar = splineargs['tempvar']
    premvar = splineargs['idvars']
    treatvar = splineargs['treatvar']
    tempbins = dsa_temperature_bin(df[df[treatvar]==0], splineargs)

    # merge the cutpoints back to the original dataset
    df = df.merge(tempbins, on=premvar, how='right')
 
    # Now construct the spline values
    df['bin_1'] = np.minimum(df['_ub_1'], df[tempvar])  
    for b in range(2, 8):
        df[f'bin_{b}'] = np.where(df[tempvar] >= df[f'_lb_{b}'], 
                                  np.minimum(df[f'_ub_{b}'] - df[f'_lb_{b}'],
                                  df[tempvar]-df[f'_lb_{b}']), 0.0)
            
    maxbin = int(df['_maxbin'].max())
    binlist = ['bin_{}'.format(i) for i in range(1, maxbin)]
        
    return df, binlist 






#============================================================================#
#	04    Construct Spline Model
#============================================================================#

def towt(df, splineargs):
    '''
    Constructs and runs the spline regression for the given df

    Parameters
    ----------
    df : pandas dataframe
        DF that contains the relevant usage and temperature (and optionally
        GP) variables for the regression. Implicitly assumes that the df
        being provided represents one customer/premise only
    splineargs : dict
        regression parameters

    Returns
    -------
    df : pandas dataframe
        the same input df, with additional column 'predicted' indicating
        the output of the regression model fit

    '''
    # Parse the spline parameters
    idvar = splineargs['idvars']
    date = splineargs['date']
    hour = splineargs['hour']
    usage = splineargs['usagevar']
    tempf = splineargs['tempvar']
    treatment = splineargs['treatvar']
    gps = splineargs['gps']
    splinemethod = splineargs['splinemethod']
    dailybool = splineargs['dailybool']
    
    # # Clean the data    
    # df[date] = pd.to_datetime(df[date], format="%m/%d/%Y")
    # df = df.dropna()
    
    # Get the list of valid seasons
    seasonlist = df['_season'].unique()

    # instantiate the result dataframe    
    result = pd.DataFrame()
    
    # loop through the seasons and run the regression on the subset
    for season in seasonlist:
        seasondf = df[df['_season'] == season]
    
        # Make the spline and merge things together
        if splinemethod =='static':
            seasondf, binlist = static_spline(seasondf, splineargs)
               
        if splinemethod == 'dynamic':
            seasondf, binlist = dynamic_spline(seasondf, splineargs)
            
        # Construct the TOW/DOW factor variables
        if not dailybool:
            seasondf['how'] = seasondf[date].dt.dayofweek * 24 + seasondf[hour]
            seasondf = pd.get_dummies(seasondf, columns=['how'])
            
            # Make the dependent variable list
            dummies = ['how_{}'.format(h) for h in range(1, 169)]
        
        if dailybool:
            seasondf['dow'] = seasondf[date].dt.dayofweek
            seasondf = pd.get_dummies(seasondf, columns=['dow'])
            
            # Make the dependent variable list
            dummies = ['dow_{}'.format(d) for d in range(0, 7)]       
         
        # Add the spline variables
        indepvars = []
        indepvars.extend(dummies)
        indepvars.extend(binlist)
        
        # Add the GPs if applicable
        if len(gps) > 0:
            indepvars.extend(gps)
        
        # Construct the regression var list for the treatment period
        x_all = seasondf[indepvars]

        # Construct the regression var list for the training period
        x = seasondf[indepvars][seasondf[treatment] == 0]
        
        # Construct the regression dependent variable    
        y = seasondf[usage][seasondf[treatment] == 0]
            
        # Run the regression
        model = sm.OLS(y.astype(float), x.astype(float)).fit()
        predictions = model.predict(x_all)
        
        # Merge predictions back to main DF
        seasondf = pd.merge(seasondf, predictions.to_frame(name='predicted'), left_index=True, right_index=True)
        
        # Clean up how dummies
        seasondf = seasondf.drop(dummies, axis=1)
        result = pd.concat([result, seasondf])
    
    
    
    
    return result

#============================================================================#
#	06    Workflow
#============================================================================#


# Define the regression parameters
seasons = {'1':1, '2':1, '3':1, '4':2, '5':2, '6':3, 
           '7':3, '8':3, '9':3, '10':2, '11':2, '12':1}
splineargs = {'idvars':'premise', 'date':'date', 'hour':'hour', 
              'treatvar':'treatment', 'gps':['gp_1', 'gp_2', 'gp_3', 'gp_4'], 'usagevar':'kwh', 
              'tempvar':'tempf', 'splinemethod':'dynamic', 'dailybool':True, 
              'seasons':seasons, 'mintempcount':20}




# Load the dataset
df = pd.read_csv(basepath + dir2 + analysis)

# Hande data prep
df = prep_data(df, splineargs)

# Construct an empty placeholder for the results
results_df = pd.DataFrame()

# Now loop through the full list of IDs and run the regression
unique_values = df[splineargs['idvars']].unique()
for acct in unique_values:
    
    # Subset the data to just that specific account
    account_df = df[df[splineargs['idvars']]==acct]
    
    # Run the regression on that specific id
    account_df = towt(account_df, splineargs)

    # Append the results
    results_df = pd.concat([results_df, account_df]) 


results_df.to_csv(basepath + dir2 + 'test_results.csv', index=False)
        
