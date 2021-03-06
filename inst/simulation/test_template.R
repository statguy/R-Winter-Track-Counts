library(devtools); install_github("statguy/Winter-Track-Counts")

library(parallel)
library(doMC)
registerDoMC(cores=detectCores())
library(STREM)
source("~/git/STREM/setup/WTC-Boot.R")

scenarios <- c("A","B","C","D","E","F")
modelNames <- c("FMPModel","SmoothModel-nbinomial-ar1","SmoothModel-nbinomial-matern-ar1")
isTest <- F
iteration <- as.integer(1)

scenario <- scenarios[6]
modelName <- modelNames[1]
mss <- getMSS(scenario=scenario, isTest=isTest)
study <- mss$study
context <- study$context
.self <- study

estimates <- study$getModel(modelName=modelName, iteration=iteration)
estimates <- study$loadEstimates(estimates=estimates)
estimates$collectEstimates()
data <- estimates$data
offsetScale <- estimates$offsetScale

habitatWeights2 <- study$getHabitatWeights(iteration=iteration)
populationSize <- study$getPopulationSize(estimates=estimates, habitatWeights=habitatWeights2)
populationSize
mean(populationSize$sizeData$Estimated)

populationSizeOverEstimate <- 1e6
