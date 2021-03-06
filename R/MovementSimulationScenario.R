MovementSimulationScenario <- setRefClass(
  Class = "MovementSimulationScenario",
  fields = list(
    study = "SimulationStudy",
    
    years = "integer",
    days = "integer",
    stepIntervalHours = "numeric",
    stepSpeedScale = "numeric",
    initialPopulation = "InitialPopulation",
    habitatWeights="ANY",
    nAgents = "integer",
    CRWCorrelation = "numeric",
    BCRWCorrelationBiasTradeoff = "ANY",
    homeRangeRadius = "ANY",
    distanceScale = "numeric",
    
    birthDeathParams = "list",
    nSteps = "integer",
    agents = "integer",
    newAgentId = "integer",
    nProposal = "integer",
    maxTry = "integer",
    debug = "logical"
    #surveyRoutes = "ANY"
  ),
  methods = list(
    initialize = function(..., distanceScale=1e3, maxTry=as.integer(100), debug=FALSE) {
      callSuper(...)
      distanceScale <<- distanceScale
      maxTry <<- maxTry
      debug <<- debug
      return(invisible(.self))
    },
    
    setup = function(response, context, nSurveyRoutes, withHabitatWeights, isTest=FALSE) {
      message("Setting up movement simulation scenario, test = ", isTest, ", habitat = ", withHabitatWeights, "...")
      
      if (inherits(BCRWCorrelationBiasTradeoff, "uninitializedField")) BCRWCorrelationBiasTradeoff <<- rep(NA, nAgents)
      if (inherits(homeRangeRadius, "uninitializedField")) homeRangeRadius <<- rep(NA, nAgents)
      nSteps.tmp <- 24 * days / stepIntervalHours
      message("Number of steps = ", nSteps.tmp, ", steps per day = ", 24 / stepIntervalHours)
      if (nSteps.tmp %% 1 != 0) stop("Number of steps must be integer.")
      nSteps <<- as.integer(nSteps.tmp)
      if (length(birthDeathParams) == 0) birthDeathParams <<- list(mean=0, sd=0.1) # 95% = 0.82 - 1.22 variation coefficient each year
      
      message("Setup study...")
      study <<- SimulationStudy(response=response)$setup(context=context, withHabitatWeights=withHabitatWeights, isTest=isTest)
      if (!missing(nSurveyRoutes)) {
        message("Setup survey routes...")
        surveyRoutes <- if (isTest) FinlandRandomWTCSurveyRoutes(study=study)$randomizeSurveyRoutes(nSurveyRoutes=nSurveyRoutes)
        else FinlandWTCSurveyRoutes(study=study)$loadSurveyRoutes(context=context, nSurveyRoutes=nSurveyRoutes)
        study$surveyRoutes <<- surveyRoutes
      }
      
      return(invisible(.self))
    },
    
    #getSurveyRoutes = function() {
    #  #return(FinlandRandomWTCSurveyRoutes$new(study=study)$randomizeSurveyRoutes(nSurveyRoutes=nSurveyRoutes))
    #  return(surveyRoutes)
    #},
    
    randomizeDistance = function(n) {
      rweibull(n, shape=2, scale=stepSpeedScale * stepIntervalHours * distanceScale)
      
      #shape = 2, scale = 2000, steps = 24/4=6
      #mean = 2000 * gamma(1+1/2) * 6 = 10634.72
      #sd = 2000 * sqrt((gamma(1+2/2) - gamma(1+1/2)^2)) * 6 = 5559.017
    },
    
    randomizeVector = function(locations) {
      library(sp)
      library(raster)
      
      if (nrow(locations) < 1 | ncol(locations) != 2 | any(is.nan(locations))) {
        print(locations)
        stop("Invalid locations argument.")
      }
      
      point <- SpatialPoints(locations[,,drop=F], proj4string=study$studyArea$proj4string)
      
      if (inherits(point, "numeric")) {
        print(locations)
        print(point)
        stop("Invalid locations argument.")
      }
      
      outsideBoundary <- is.na(over(point, study$studyArea$boundary))
      if (class(outsideBoundary) == "matrix") outsideBoundary <- outsideBoundary[,1]
      
      if (inherits(habitatWeights, "uninitializedField") | is.null(habitatWeights)) {
        if (all(outsideBoundary == TRUE)) return(NULL)
        return(list(index=1, coords=locations[1,,drop=F]))
      }
      else {
        habitatTypes <- raster::extract(study$studyArea$habitat, locations)
        w <- habitatWeights$getWeights(habitatTypes)
        w[outsideBoundary] <- 0
        
        if (all(w == 0)) return(NULL)
        k <- sample(1:nrow(locations), 1, prob=w)
        return(list(index=k, coords=locations[k,,drop=F]))
      }
    },
    
    randomizeBCRWTrack = function(initialLocation, initialAngle, isFirst, CRWCorrelation, BCRWCorrelationBiasTradeoff, homeRangeRadius) {
      library(CircStats)
      library(sp)
      
      coords <- matrix(NA, nrow=nSteps + 1, ncol=2)
      coords[1,] <- initialLocation
      angles <- numeric(nSteps + 1)
      angles[1] <- initialAngle
      
      step <- 2
      proposedVectorsFailed <- matrix(ncol=2)
      
      while (TRUE) {
        for (j in 1:maxTry) {
          # Correlated random walk
          newAngles <- rwrpnorm(nProposal, angles[step-1], CRWCorrelation)
          #newDistances <- rweibull(nProposal, shape=2, scale=stepSpeedScale * stepIntervalHours * distanceScale)
          newDistances <- randomizeDistance(nProposal)
          
          if (length(homeRangeRadius) != 0 & !is.na(homeRangeRadius)) {
            if (step > 2 & euclidean(coords[1,,drop=F], coords[step-1,,drop=F]) > homeRangeRadius) {
              # Biased correlated random walk
              xy <- matrix(coords[1,,drop=F], ncol=2, nrow=nProposal, byrow=T) - matrix(coords[step-1,,drop=F], ncol=2, nrow=nProposal, byrow=T)
              angleBias <- atan2(xy[,2], xy[,1])
              newAngles <- Arg(BCRWCorrelationBiasTradeoff * exp(complex(imaginary=newAngles)) + (1 - BCRWCorrelationBiasTradeoff) * exp(complex(imaginary=angleBias)))
            }
          }
          
          proposedVectors <- getVector(coords[step-1,,drop=F], newDistances, newAngles)
          acceptedVectors <- randomizeVector(locations=proposedVectors)
          
          if (!is.null(acceptedVectors)) {
            coords[step,] <- acceptedVectors$coords
            angles[step] <- newAngles[acceptedVectors$index]
            proposedVectorsFailed <- matrix(ncol=2)
            break
          }
          else {
            # Vector is pointing outside the boundary or there is only unknown habitat.
            # Go back one step and try again, so we don't get stuck.
            step <- step - 1
            if (step < 2) step <- 2
            proposedVectorsFailed <- rbind(proposedVectorsFailed, proposedVectors)
            next
          }
        }
        
        if (j == maxTry) { # This happens "too often", but why? TODO: fix
          fileName <- file.path(getwd(), "boundary_reflection_failed_points.RData")
          save(coords, proposedVectors, acceptedVectors, step, proposedVectorsFailed[-1,], file=fileName) # TODO: unidentified bug here, fix
          stop("Boundary reflection failed. File saved to ", fileName)
          
          x <- range(coords[,1], proposedVectors[,1], acceptedVectors[,1], na.rm=T) + c(-1,1) * 1e4
          y <- range(coords[,2], proposedVectors[,2], acceptedVectors[,2], na.rm=T) + c(-1,1) * 1e4
          plot(x, y, type="n")
          plot(study$studyArea$boundary, add=T)
          points(coords, col="darkgreen")
          points(coords[step-1,,drop=F], col="green")
          points(proposedVectorsFailed, col="darkred")
        }
        
        if (step == nSteps + 1) break
        step <- step + 1
      }
      
      index <- if (isFirst) 1:nSteps else 1:nSteps+1
      stepDays <- rep(1:days, each=24 / stepIntervalHours)
      stepHours <- rep(seq(0, 24-stepIntervalHours, by=stepIntervalHours), days)
      stepMinutes <- (stepHours - trunc(stepHours)) * 60
      stepSeconds <- (stepMinutes - trunc(stepMinutes)) * 60
      return(data.frame(x=coords[index,1], y=coords[index,2], angle=angles[index], day=stepDays, hour=trunc(stepHours), minute=trunc(stepMinutes), second=round(stepSeconds)))
    },
    
    # Combined birth-death process:
    # 0 born = individual dies/emigrates
    # 1 born = individual survives to the next year
    # 2 born = 1 parent survives + 1 offspring/immigration
    # etc.
    randomizeBirthDeath = function() {
      if (length(birthDeathParams) == 0)
        stop("Set birthDeathParams parameter.")
      
      bdRate <- if (birthDeathParams$sd == 0) birthDeathParams$mean
      else rlnorm(n=1, meanlog=birthDeathParams$mean, sdlog=birthDeathParams$sd)
      nTransform <- rpois(length(agents), bdRate)
      
      nBorn <- sum(nTransform[nTransform > 1] - 1)
      nSurvive <- sum(nTransform[nTransform == 1]) + length(nTransform[nTransform > 1])
      nDie <- length(nTransform[nTransform == 0])
      
      message("agents before = ", length(agents), " -> born = ", nBorn, ", survive = ", nSurvive, ", die = ", nDie, " -> agents after = ", nSurvive + nBorn)
      
      survivedIndex <- nTransform > 0      
      bornIndex <- nTransform > 1
      x <- rep(which(bornIndex), nTransform[bornIndex] - 1)
      survivedBornIndex <- c(which(survivedIndex), x)
      
      agents <<- agents[survivedIndex]
      if (nBorn > 0) agents <<- c(agents, newAgentId:(newAgentId + nBorn - 1))
      newAgentId <<- as.integer(newAgentId + nBorn)
      
      herdSize <- randomizeHerdSize()
      
      return(list(survivedBornIndex=survivedBornIndex, herdSize=herdSize))
    },
    
    randomizeHerdSize = function() {
      return(rep(1, length(agents)))
    },
    
    randomizeBCRWTracks = function(iteration) {
      library(raster)
      library(plyr)
      library(maptools)
      library(rgdal)
      
      initialLocations <- initialPopulation$randomize(nAgents)
      habitatTypes <- raster::extract(study$studyArea$habitat, initialLocations)
      if (inherits(habitatWeights, "uninitializedField") | is.null(habitatWeights)) {
        if (any(is.na(habitatTypes))) stop("Invalid initial coordinates.")
        nProposal <<- as.integer(1)
      }
      else {
        if (any(habitatWeights$getWeights(habitatTypes) == 0)) stop("Invalid initial coordinates.")
        nProposal <<- as.integer(10)
      }
      message("Number of proposals = ", nProposal)
      
      agents <<- 1:nAgents
      newAgentId <<- as.integer(nAgents + 1)
      herdSize <- randomizeHerdSize()
      
      tracks <- data.frame()
      initialLocations <- coordinates(initialLocations)
      initialAngles <- runif(nAgents, 0, 2*pi)
      isFirst <- TRUE
      
      nAgentsCurrent <- nAgents
      
      for (year in 1:years) {
        if (nAgentsCurrent > 0) {
          track <- ldply(1:nAgentsCurrent,
            function(agentIndex, initialLocations, initialAngles, nAgentsCurrent, isFirst, iteration) {              
              message("Iteration = ", iteration, ", agent (", agents[agentIndex], ") = ", agentIndex, " / ", nAgentsCurrent, ", year = ", year,  " / ", years, ", days = ", days, ", herd size = ", herdSize[agentIndex], "...")
              track <- randomizeBCRWTrack(initialLocation=initialLocations[agentIndex,,drop=F],
                                         initialAngle=initialAngles[agentIndex],
                                         isFirst=isFirst,
                                         CRWCorrelation=CRWCorrelation,
                                         BCRWCorrelationBiasTradeoff=BCRWCorrelationBiasTradeoff[agentIndex],
                                         homeRangeRadius=homeRangeRadius[agentIndex])
              track$id <- agents[agentIndex]
              track$herdSize <- herdSize[agentIndex]
              
              return(track)
            }, initialLocations=initialLocations, initialAngles=initialAngles, nAgentsCurrent=nAgentsCurrent, isFirst=isFirst, iteration=iteration, .parallel=TRUE & !debug, .inform=debug)
          
          if (year < years) {
            rdReturn <- randomizeBirthDeath()
            survivedBornLastStepIndex <- rdReturn$survivedBornIndex * nSteps
            initialLocations <- as.matrix(track[survivedBornLastStepIndex, c("x","y"), drop=F])
            initialAngles <- track[survivedBornLastStepIndex, c("angle")]
            isFirst <- FALSE
            nAgentsCurrent <- length(agents)
            herdSize <- rdReturn$herdSize
          }        

          track$year <- year
          track$date <- as.POSIXct(strptime(paste(2000+track$year, track$day, track$hour, track$minute, track$second), format="%Y %j %H %M %S"))
          month <- as.POSIXlt(track$date)$mon + 1
          retainMonths <- c(1,2)
          retainIndex <- month %in% retainMonths
          track <- track[retainIndex,]
          track <- addDtDist(track)
          
          tracks <- rbind(tracks, track)
        }
        
        # TODO: if no agents, randomize new immigrating ones
      }
      
      return(tracks)
    },
    
    simulate = function(iteration, save=TRUE) {
      tracksDF <- randomizeBCRWTracks(iteration=as.integer(iteration))
      tracks <- SimulatedTracks(study=study, preprocessData=save, xy=tracksDF[,c("x","y")], id=tracksDF$id, date=tracksDF$date, dt=tracksDF$dt, dist=tracksDF$dist, burst=tracksDF$burst, year=tracksDF$year, yday=tracksDF$yday, iteration=as.integer(iteration), herdSize=tracksDF$herdSize)
      return(invisible(tracks))
    },
    
    simulateMultiple = function(nIterations=as.integer(50), restartIteration=1, iterationVector=1:nIterations, save=FALSE) {
      #nIterations <<- nIterations
      stopifnot(restartIteration <= nIterations)
      
      simulatedTracks <- SimulatedTracksCollection(study=study)
      for (i in restartIteration:nIterations) {
        message("Iteration ", i, " of ", nIterations, "...")
        tracksDF <- randomizeBCRWTracks(iteration=i)
        tracks <- SimulatedTracks(study=study, preprocessData=save, xy=tracksDF[,c("x","y")], id=tracksDF$id, date=tracksDF$date, dt=tracksDF$dt, dist=tracksDF$dist, burst=tracksDF$burst, year=tracksDF$year, yday=tracksDF$yday, iteration=i, herdSize=tracksDF$herdSize)
        simulatedTracks$addTracks(tracks)
      }
      
      return(invisible(simulatedTracks))
    },
    
    hasHabitatWeights = function() {
      return(!inherits(habitatWeights, "uninitializedField"))
    }
  )
)

# Correlated random walk in a homogeneous landscape, random initial locations
MovementSimulationScenarioA <- setRefClass(
  Class = "MovementSimulationScenarioA",
  contains = "MovementSimulationScenario",
  methods = list(
    initialize = function(nAgents=as.integer(200), years=as.integer(20), days=as.integer(365), stepIntervalHours=4, CRWCorrelation=0.7, ...) {
      callSuper(years=years, nAgents=nAgents, days=days, stepIntervalHours=stepIntervalHours, stepSpeedScale=0.5, CRWCorrelation=CRWCorrelation, ...)
      return(invisible(.self))
    },
    
    setup = function(context, response="A", nSurveyRoutes=500, isTest=F) {
      callSuper(context=context, response=response, nSurveyRoutes=nSurveyRoutes, withHabitatWeights=FALSE, isTest=isTest)
      initialPopulation <<- RandomInitialPopulation(studyArea=study$studyArea)      
      return(invisible(.self))
    }    
  )
)

# Biased correlated random walk in a homogenous landscape, random initial locations
# 10% of the agents are simulated like in the scenario A
MovementSimulationScenarioB <- setRefClass(
  Class = "MovementSimulationScenarioB",
  contains = "MovementSimulationScenario",
  fields = list(
  ),
  methods = list(
    initialize = function(nAgents=as.integer(200), years=as.integer(20), days=as.integer(365), stepIntervalHours=4, CRWCorrelation=0.7, BCRWCorrelationBiasTradeoff=0.3, homeRangeRadius=10000, ...) {
      callSuper(years=years, nAgents=nAgents, days=days, stepIntervalHours=stepIntervalHours, stepSpeedScale=0.5, CRWCorrelation=CRWCorrelation, BCRWCorrelationBiasTradeoff=BCRWCorrelationBiasTradeoff, homeRangeRadius=homeRangeRadius, ...)
      setAgents()
      return(invisible(.self))
    },
    
    setAgents = function() {
      pAgentsA <- 0.1
      nAgentsA <- round(pAgentsA * nAgents)
      nAgentsB <- nAgents - nAgentsA
      BCRWCorrelationBiasTradeoff <<- c(rep(NA, nAgentsA), rep(BCRWCorrelationBiasTradeoff, nAgentsB))
      homeRangeRadius <<- c(rep(NA, nAgentsA), rep(homeRangeRadius, nAgentsB))      
    },
    
    setup = function(context, response="B", nSurveyRoutes=500, isTest=F) {
      callSuper(context=context, response=response, nSurveyRoutes=nSurveyRoutes, withHabitatWeights=FALSE, isTest=isTest)
      initialPopulation <<- RandomInitialPopulation(studyArea=study$studyArea)
      return(invisible(.self))
    }
  )
)

# Same as scenario A, but with animals moving in groups
MovementSimulationScenarioC <- setRefClass(
  Class = "MovementSimulationScenarioC",
  contains = "MovementSimulationScenario",
  fields = list(
    averageHerdSize = "integer"
  ),
  methods = list(
    initialize = function(nAgents=as.integer(200/5), years=as.integer(20), days=as.integer(365), stepIntervalHours=4, CRWCorrelation=0.7, averageHerdSize=as.integer(4), ...) {
      if (nAgents < 1) stop("Invalid number of agents.")
      callSuper(years=years, nAgents=nAgents, days=days, stepIntervalHours=stepIntervalHours, stepSpeedScale=0.5, CRWCorrelation=CRWCorrelation, ...)
      averageHerdSize <<- averageHerdSize
      return(invisible(.self))
    },
    
    setup = function(context, response="C", nSurveyRoutes=500, isTest=F) {
      callSuper(context=context, response=response, nSurveyRoutes=nSurveyRoutes, withHabitatWeights=FALSE, isTest=isTest)
      initialPopulation <<- RandomInitialPopulation(studyArea=study$studyArea)
      return(invisible(.self))
    },
    
    randomizeHerdSize = function() {
      return(rpois(length(agents), averageHerdSize) + 1)
    }
  )
)

# Same as scenario A, but with clustered initial locations
MovementSimulationScenarioD <- setRefClass(
  Class = "MovementSimulationScenarioD",
  contains = "MovementSimulationScenario",
  methods = list(
    initialize = function(nAgents=as.integer(200), years=as.integer(20), days=as.integer(365), stepIntervalHours=4, CRWCorrelation=0.7, ...) {
      callSuper(years=years, nAgents=nAgents, days=days, stepIntervalHours=stepIntervalHours, stepSpeedScale=0.5, CRWCorrelation=CRWCorrelation, ...)
      return(invisible(.self))
    },
    
    setup = function(context, response="D", nSurveyRoutes=500, sampleInitial=F, isTest=F, range=100e3, sigma=4, max.edge=3000) {
      callSuper(context=context, response=response, nSurveyRoutes=nSurveyRoutes, withHabitatWeights=FALSE, isTest=isTest)
      if (sampleInitial) {
        initialPopulation <<- if (isTest) ClusteredInitialPopulation(studyArea=study$studyArea, range=range, sigma=sigma, max.edge=max.edge)
        else ClusteredInitialPopulation(studyArea=study$studyArea)
      }
      return(invisible(.self))
    }
  )
)

# Same as scenario A, but movements occur on heterogenous landscape
MovementSimulationScenarioE <- setRefClass(
  Class = "MovementSimulationScenarioE",
  contains = "MovementSimulationScenario",
  methods = list(
    initialize = function(nAgents=as.integer(200), years=as.integer(20), days=as.integer(365), stepIntervalHours=4, CRWCorrelation=0.7, ...) {
      callSuper(years=years, nAgents=nAgents, days=days, stepIntervalHours=stepIntervalHours, stepSpeedScale=0.5, CRWCorrelation=CRWCorrelation, ...)
      return(invisible(.self))
    },
    
    setup = function(context, response="E", nSurveyRoutes=500, isTest=F, range=Inf, sigma=1, readHabitatIntoMemory=F) {
      if (isTest) if (length(nSurveyRoutes) == 0) stop("Provide the number of survey routes.")
      
      callSuper(context=context, response=response, nSurveyRoutes=1, withHabitatWeights=TRUE, isTest=isTest)
      
      if (readHabitatIntoMemory) {
        study$studyArea$readRasterIntoMemory()
        
        samplingWeights <- CORINEHabitatWeights(list(Urban=0.1, Agriculture=0.1, Forestland=1, Peatland=0.5, Water=0))
        initialPopulation <<- if (isTest) ClusteredInitialPopulation(studyArea=study$studyArea, range=range, sigma=sigma, max.edge=3000, habitatWeights=samplingWeights)
        else ClusteredInitialPopulation(studyArea=study$studyArea, range=range, sigma=sigma, habitatWeights=samplingWeights)
      
        habitatWeights <<- CORINEHabitatWeights(list(Urban=0.1, Agriculture=0.1, Forestland=1, Peatland=0.5, Water=0.05))
      }
      #if (isTest)
      #  surveyRoutes <<- FinlandRandomForestWTCSurveyRoutes$new(study=study)$randomizeSurveyRoutes(nSurveyRoutes=nSurveyRoutes)
      
      transects <- FinlandRandomForestWTCSurveyRoutes$new(study=study)
      transects$loadSurveyRoutes()
      #surveyRoutes <<- transects
      #study$surveyRoutes <<- surveyRoutes
      study$surveyRoutes <<- transects
      
      return(invisible(.self))
    }
  )
)

# Combines scenarios B-E
MovementSimulationScenarioF <- setRefClass(
  Class = "MovementSimulationScenarioF",
  contains = c("MovementSimulationScenarioE", "MovementSimulationScenarioC", "MovementSimulationScenarioB"),
  methods = list(
    initialize = function(nAgents=as.integer(200/5), years=as.integer(20), days=as.integer(365), stepIntervalHours=4, CRWCorrelation=0.7, BCRWCorrelationBiasTradeoff=0.3, homeRangeRadius=10000, averageHerdSize=as.integer(4), ...) {
      if (nAgents < 1) stop("Invalid number of agents.")
      callSuper(years=years, nAgents=nAgents, days=days, stepIntervalHours=stepIntervalHours, stepSpeedScale=0.5, CRWCorrelation=CRWCorrelation, BCRWCorrelationBiasTradeoff=BCRWCorrelationBiasTradeoff, homeRangeRadius=homeRangeRadius, averageHerdSize=averageHerdSize, ...)
      setAgents()
      return(invisible(.self))
    },
    
    setup = function(context, response="F", nSurveyRoutes=500, sampleInitial=F, isTest=F, readHabitatIntoMemory=F) {
      callSuper(context=context, response=response, nSurveyRoutes=1, isTest=isTest, range=100e3, sigma=4, readHabitatIntoMemory=readHabitatIntoMemory)
      
      transects <- FinlandRandomForestWTCSurveyRoutes$new(study=study)
      transects$loadSurveyRoutes()
      #surveyRoutes <<- transects
      #study$surveyRoutes <<- surveyRoutes
      study$surveyRoutes <<- transects
      
      return(invisible(.self))
    },
    
    randomizeHerdSize = function() {
      return(rpois(length(agents), averageHerdSize) + 1)
    }
  )
)
