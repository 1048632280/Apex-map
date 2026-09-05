package main

import "time"

const (
	apexStatusAPIURL    = "https://api.apexlegendsstatus.com/maprotation"
	apexStatusAPIKeyEnv = "APEX_LEGENDS_STATUS_API_KEY"
	defaultPort         = 4173
	publicDirectoryName = "public"
	stateDirectoryName  = "data"
	stateFileName       = "rotation-state.json"
	pollInterval        = time.Minute
	requestTimeout      = 15 * time.Second
	boundaryExtraDelay  = 1500 * time.Millisecond
	minBoundaryDelay    = 5 * time.Second
	memoryWriteInterval = 30 * time.Minute
	transitionMaxAge    = 14 * 24 * time.Hour
)
