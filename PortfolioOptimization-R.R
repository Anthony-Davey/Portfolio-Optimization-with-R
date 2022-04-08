library(tidyverse)
library(tidyquant)

install.packages('ROI')
install.packages('ROI.plugin.glpk')
install.packages('ROI.plugin.quadprog')
install.packages('ROI.plugin.symphony')

install.packages("PortfolioAnalytics")
library(PortfolioAnalytics)

#obtain dataframe of ticker data for stocks below
tickers <- tq_get(c("COST", "GOOG", "AMZN", "ANTM", "KO"),
                  from = "2005-01-01") %>%
                  group_by(symbol) %>%
                  tq_transmute(select = adjusted,
                               mutate_fun = periodReturn,
                               period = "monthly",
                               col_rename = "ret")


#this flips the dataframes so that tickers are in the columns
#timetk function comes from timetk package but since its not loaded and we just want this 
#one functionality we can call it using ::
stocks_wide <- tickers %>% pivot_wider(names_from = symbol, values_from = ret) %>%
                timetk::tk_xts(date_var = date)

#Step3: Find optimal portfolio weights;
#3.0 Define portfolio specification name
port_spec <- portfolio.spec(colnames(stocks_wide))  # Tells R to use the column names from our xts object (which are stock names)

#3.1 Add constraints. First constraint says to use all assets (the sum of weights is one)
port_spec <- add.constraint(portfolio = port_spec,
                            type = "weight_sum",
                            min_sum= 0.99,
                            max_sum =1.01) # First constraints tells R to use all assets (the sum of weights adds to one)

port_spec <- add.constraint(portfolio = port_spec,
                            type ="box",
                            min =0,
                            max =1)        #Second constraints tells R to use anywhere between 0 and 100% of each assets. 
#We can restrict any one investment to say below 50% here.

#3.2 Add objective. Because we want risk-adjusted return, we need to specify both a risk and a return objective 
port_spec <- add.objective(portfolio = port_spec,
                           type = "risk",
                           name = 'StdDev')
port_spec <- add.objective(portfolio = port_spec,
                           type = "return",
                           name ="mean")
print(port_spec)       


#Step 4: Run optimization (there will be no output except for a warning message. The output is stored in opt object printed below)
opt <- optimize.portfolio(stocks_wide, portfolio = port_spec,
                          optimize_method = "ROI",
                          trace = TRUE, 
                          maxSR = TRUE)
print(opt) #let's see what we have


#Step 5: Charting
chart.EfficientFrontier(opt, match.col = "StdDev")

#Step 6: Extracting weights
wt <- extractWeights(opt)

#Step 7:  Calculate optimal portfolio returns
wt_1 <- as.data.frame(wt) %>% rownames_to_column(var ="symbol")   # Convert the weights into a dataframe and create a variable name: symbol.


#create optimal portfolio based on wt_1 calculated
optimal_port <- tickers %>% tq_portfolio(assets_col = symbol,
                                        returns_col = ret,
                                        weights = wt_1,
                                        col_rename = 'pret')

#comparing to a equally weighted portfolio of the same tickers
myport <- tickers %>% tq_portfolio(assets_col = symbol,
                                   returns_col = ret,
                                   weights = c(0.2,0.2,0.2,0.2,0.2),
                                   col_rename = 'pret')


#risk-adjusted ratios
opSort <- optimal_port %>% tq_performance(
  Ra = pret,
  MAR =0,
  performance_fun = SortinoRatio
) %>% add_column(symbol = "optimal_port", .before =1)

mySort <- myport %>% tq_performance(
  Ra = pret,
  MAR =0,
  performance_fun = SortinoRatio
) %>% add_column(symbol = "myport", .before =1)


opSharpe <- optimal_port %>% tq_performance(
  Ra = pret,
  performance_fun = SharpeRatio,
  FUN = "StdDev"
) %>% add_column(symbol = "optimal_port", .before =1)

mySharpe <- myport %>% tq_performance(
  Ra = pret,
  performance_fun = SharpeRatio,
  FUN = "StdDev"
) %>% add_column(symbol = "myport", .before =1)


opSterl <- optimal_port %>% tq_performance(
  Ra = pret,
  Rb = NULL,
  performance_fun = SterlingRatio
) %>% add_column(symbol = "optimal_port", .before =1)

mySterl <- myport %>% tq_performance(
  Ra = pret,
  Rb = NULL,
  performance_fun = SterlingRatio
) %>% add_column(symbol = "myport", .before =1)


#binding by rows and combining data in to plotable format
all_sort <- rbind(mySort, opSort)
all_sharpe <- rbind(mySharpe, opSharpe)
all_sterl <- rbind(mySterl, opSterl)
fun_combined <- inner_join(all_sort, all_sharpe)
fun_combined2 <- inner_join(fun_combined, all_sterl)

fun_combined3 <- fun_combined2 %>%
  pivot_longer(!symbol, names_to = "measure", values_to = "value")

#plot data
fun_combined3 %>%
  ggplot(aes(measure, abs(value), fill = symbol))+geom_bar(stat = "identity", position = "dodge")
