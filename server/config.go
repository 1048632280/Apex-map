package main

import "time"

const (
	apexRankedAPIURL    = "https://apexranked.com/api/ranked-map"
	defaultPort         = 4173
	publicDirectoryName = "public"
	pollInterval        = time.Minute
	requestTimeout      = 15 * time.Second
	boundaryExtraDelay  = 1500 * time.Millisecond
	minBoundaryDelay    = 5 * time.Second
)
