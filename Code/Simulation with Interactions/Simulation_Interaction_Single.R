library(foreach)
library(doParallel)

set.seed(19991109, kind = "L'Ecuyer-CMRG")

# Initialize parallel backend
cl <- makeCluster(8)

# Register the parallel backend
registerDoParallel(cl)


S = 10000
result = foreach (i = 1:S, .combine = 'rbind', .errorhandling='remove') %dopar% {
  library(tidyverse)
  library(lme4)
  n <- 100 
  t <- 10
  t_treat <- 5
  
  delta <- 5
  gamma <- 3
  rho <- 8
  phi = 2
  
  A <- rnorm(n)
  X <- runif(n, 0, 10)
  
  X_it = c()
  for (j in 1:n){
    X_it = c(X_it, rnorm(n = t, mean = X[j], sd = 1))
  }
  
  p = ifelse(A >= 1, 0.7, 0.3)
  D <- rbinom(n, 1, p)
  
  
  dat = tidyr::expand_grid(data.frame(id = 1:n, A = A, D = D), Time = 1:t) %>% 
    mutate(X_it = X_it) %>% 
    mutate(time = factor(Time), id = factor(id)) %>% 
    mutate(Time_to_treat = ifelse(Time < t_treat, 0, 1)) %>% 
    mutate(D_it = D * Time_to_treat) %>% 
    mutate(epsilon = rnorm(n*t, mean = 0, sd = 1)) %>% 
    mutate(Y = (Time)^2 + gamma*A + delta*X_it + rho*D_it + phi*A*D_it + epsilon)
  
  # dat %>% ggplot(aes(x = Time, y = Y, group = factor(id), color = factor(D))) + geom_line() + facet_wrap(~factor(D))

  # DID estimator
  bar_Y_1_t2 = dat %>% filter(Time == t_treat, D == 1) %>% summarise(mean(Y)) %>% as.numeric()
  bar_Y_1_t1 = dat %>% filter(Time == t_treat-1, D == 1) %>% summarise(mean(Y)) %>% as.numeric()
  
  bar_Y_0_t2 = dat %>% filter(Time == t_treat, D == 0) %>% summarise(mean(Y)) %>% as.numeric()
  bar_Y_0_t1 = dat %>% filter(Time == t_treat-1, D == 0) %>% summarise(mean(Y)) %>% as.numeric()
  
  DID_est = (bar_Y_1_t2 - bar_Y_1_t1) - (bar_Y_0_t2 - bar_Y_0_t1)
  DID_bias = DID_est - rho
  
  # OLS
  mod0 = lm(Y ~ X_it + time + D_it, dat)
  # summary(mod0)
  # tail(confint(mod0),1)
  OLS_est = tail(mod0$coefficients, 1)
  OLS_bias = (OLS_est - rho) %>% as.numeric()
  OLS_CI = tail(confint(mod0),1)[1] < rho & rho < tail(confint(mod0),1)[2]

  # fixed-effects model
  mod1 = lm(Y ~ id + X_it + time + D_it - 1, dat)
  # summary(mod1)
  # tail(confint(mod1),1)
  FE_est = tail(mod1$coefficients, 1)
  FE_bias = (FE_est - rho) %>% as.numeric()
  FE_CI = tail(confint(mod1),1)[1] < rho & rho < tail(confint(mod1),1)[2]
  
  # random-effects model (with random intercept)
  mod2 = lme4::lmer(Y ~ X_it + time + D_it + (1 | id) - 1, dat)
  summ_lmer = summary(mod2)
  # summ_lmer
  # tail(confint(mod2),1)
  RE_est = tail(summ_lmer$coefficients,1)[1]
  RE_bias = (RE_est - rho) %>% as.numeric()
  RE_ci =  tail(confint(mod2, method="Wald"),1)
  RE_CI = RE_ci[1] < rho & rho < RE_ci[2]
  
  
  res_est = c(DID_est, OLS_est, FE_est, RE_est)
  res_bias = c(DID_bias, OLS_bias, FE_bias, RE_bias)
  CI_capture = c(OLS_CI, FE_CI, RE_CI)
  # c(res_est, res_bias, CI_capture)
  return(c(res_est, res_bias, CI_capture))
}

colnames(result) = c("DID_est", "OLS_est", "FE_est", "RE_est", 
                     "DID_bias", "OLS_bias", "FE_bias", "RE_bias",
                     "OLS_CI", "FE_CI", "RE_CI")
colMeans(result)


