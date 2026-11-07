-- Job flavour for Silver State Express, one module per kind of job.
local jobs = {}
jobs.rush = require("jobs_rush")
jobs.milk = require("jobs_milk")
jobs.ice = require("jobs_ice")
jobs.cake = require("jobs_cake")
return jobs
