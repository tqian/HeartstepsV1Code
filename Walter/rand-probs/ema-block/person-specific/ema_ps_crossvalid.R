## Pre-clear the global memory
rm(list =  ls())

## Parallel compute setup
library(doParallel)
cl <- makeCluster(30)
registerDoParallel(cl)

## Required packages and source files
## setwd("/Users/walterdempsey/Documents/github/heartstepsdata/Walter/rand-probs/ema-block/person-specific")
source("ema_ps_functions.R"); require(mgcv); require(chron); require(foreach); require(doRNG); require(lme4)

setwd("/n/murphy_lab/users/wdempsey/ubicomp/data/")
# setwd("/Volumes/dav/HeartSteps/Walter")
window.time = read.csv("window_time.csv")
# Sedentary.values = read.csv("sed_values.csv")
# Sedentary.length = read.csv("sed_length.csv")
setwd("/n/murphy_lab/users/wdempsey/ubicomp/ema-block/person-specific")
# setwd("~/Documents/github/heartstepsdata/Walter/rand-probs/ema-block/person-specific")
bucket1 = c(14,17); bucket2 = c(18,21); bucket3 = c(22,1)
buckets = list(bucket1,bucket2, bucket3)

window.time$window.utime = as.POSIXct(window.time$window.utime, tz = "GMT")

## Create a data.frame for Expected time Remaining
## Range of current hour = c(14:23,0:1)
seq.hour = c(14:23,0:1)

## Build data aggregations per bucket
## For all user-day pairs
data.buckets = construct.data.buckets(window.time, buckets)

## Setup
init.N = 0.5

## Extract a person-day
set.seed("139137")
all.persondays = unique(window.time[,c(1,3)])

## Generate the 5 random partitions of the people
unique.users = unique(all.persondays$user)
partitions = sample(unique.users, length(unique.users), replace = FALSE)
block.size = ceiling(length(unique.users)/5)

all.persondays[,3] = unlist(lapply(all.persondays$user, which.partition))

all.persondays = data.frame(all.persondays)
names(all.persondays) = c("user", "study.day", "block")

## Build the models for each partition
## Model is bucket specific
model.buckets = construct.model.buckets(data.buckets, all.persondays)

## Compute offsets
offset.list = list()
N = 0.53

for (blockid in 1:5) {
  offset.list[[blockid]] = otherblock.assignment.fn(all.persondays, blockid, N.one, data.buckets, model.buckets, 0)/3
}

if (!file.exists("simulation_At.RDS")) {
  # total.At = sapply(1:nrow(all.persondays), cv.assignment.fn, all.persondays, all.Ns)
  total.At = foreach(i=1:nrow(all.persondays), .packages = c("mgcv", "chron"), .combine = cbind, .options.RNG =541891) %dorng% cv.assignment.fn(i,all.persondays, N, data.buckets, model.buckets, offset.list)
  saveRDS(total.At, file = "simulation_At.RDS")
} else {
  total.At = readRDS("simulation_At.RDS")
}
mean(colSums(total.At[1:144,]), na.rm = TRUE)
sd(colSums(total.At[1:144,]), na.rm = TRUE)/sqrt(nrow(all.persondays))

## Calculate p.hat per person-day
## Only compute if file doesn't exist
if (!file.exists("simulation_phat.RDS")) {
  num.iters = 1000
  total.phat = foreach(i=1:nrow(all.persondays), .packages = c("mgcv", "chron"), .combine = cbind, .options.RNG =541891) %dorng% cv.assignment.multiple.fn(i,all.persondays, N, num.iters, data.buckets, model.buckets, offset.list)
  saveRDS(total.phat, file = "simulation_phat.RDS")
} else {
  total.phat = readRDS("simulation_phat.RDS")
}
