package main

import (
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	defaultPort         = 4173
	apiURL              = "https://apexranked.com/api/ranked-map"
	pollInterval        = time.Minute
	requestTimeout      = 15 * time.Second
	boundaryExtraDelay  = 1500 * time.Millisecond
	minBoundaryDelay    = 5 * time.Second
)

//go:embed index.html styles.css app.js manifest.webmanifest image/*
var staticFiles embed.FS

type mapData struct {
	Key             string `json:"key"`
	Slug            string `json:"slug"`
	Name            string `json:"name"`
	StartsAt        string `json:"starts_at"`
	EndsAt          string `json:"ends_at"`
	DurationMinutes int    `json:"duration_minutes"`
	IsCurrent       bool   `json:"is_current"`
}

type apiSchedule struct {
	Current     mapData   `json:"current"`
	Next        mapData   `json:"next"`
	Upcoming    []mapData `json:"upcoming"`
	CycleMinutes int      `json:"cycle_minutes"`
}

type publicState struct {
	Data      *apiSchedule `json:"data"`
	Online    bool         `json:"online"`
	FetchedAt *time.Time   `json:"fetchedAt"`
}

var (
	stateMu      sync.RWMutex
	refreshMu    sync.Mutex
	boundaryMu   sync.Mutex
	boundaryTimer *time.Timer
	latestState  = publicState{}
)

func configuredPort() int {
	value, err := strconv.Atoi(os.Getenv("PORT"))
	if err != nil || value < 1 || value > 65535 {
		return defaultPort
	}
	return value
}

func configuredAPIURL() string {
	if value := strings.TrimSpace(os.Getenv("APEXRANKED_API_URL")); value != "" {
		return value
	}
	return apiURL
}

func normalizeMap(item mapData) (mapData, error) {
	if item.Key == "" || item.Slug == "" || item.Name == "" || item.StartsAt == "" || item.EndsAt == "" {
		return mapData{}, fmt.Errorf("API 未返回完整地图数据")
	}

	startsAt, err := time.Parse(time.RFC3339, item.StartsAt)
	if err != nil {
		return mapData{}, fmt.Errorf("API 返回的开始时间无效: %w", err)
	}
	endsAt, err := time.Parse(time.RFC3339, item.EndsAt)
	if err != nil || !endsAt.After(startsAt) {
		return mapData{}, fmt.Errorf("API 返回的结束时间无效")
	}

	if item.DurationMinutes <= 0 {
		item.DurationMinutes = int(endsAt.Sub(startsAt).Minutes())
	}
	item.IsCurrent = false
	return item, nil
}

func normalizeSchedule(payload apiSchedule) (apiSchedule, error) {
	if len(payload.Upcoming) < 3 {
		return apiSchedule{}, fmt.Errorf("API 未返回完整的 upcoming 数据")
	}

	current, err := normalizeMap(payload.Current)
	if err != nil {
		return apiSchedule{}, err
	}
	next, err := normalizeMap(payload.Next)
	if err != nil {
		return apiSchedule{}, err
	}

	upcoming := make([]mapData, 3)
	for index, item := range payload.Upcoming[:3] {
		upcoming[index], err = normalizeMap(item)
		if err != nil {
			return apiSchedule{}, err
		}
	}

	current.IsCurrent = true
	next.IsCurrent = false
	upcoming[0] = current
	upcoming[1] = next
	upcoming[2].IsCurrent = false

	return apiSchedule{
		Current:      current,
		Next:         next,
		Upcoming:     upcoming,
		CycleMinutes: payload.CycleMinutes,
	}, nil
}

func fetchSchedule(ctx context.Context) (apiSchedule, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, configuredAPIURL(), nil)
	if err != nil {
		return apiSchedule{}, err
	}

	client := http.Client{Timeout: requestTimeout}
	response, err := client.Do(request)
	if err != nil {
		return apiSchedule{}, err
	}
	defer response.Body.Close()

	if response.StatusCode < http.StatusOK || response.StatusCode >= http.StatusMultipleChoices {
		return apiSchedule{}, fmt.Errorf("API 请求失败: %s", response.Status)
	}

	var payload apiSchedule
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		return apiSchedule{}, err
	}

	return normalizeSchedule(payload)
}

func resetBoundaryTimer() {
	boundaryMu.Lock()
	defer boundaryMu.Unlock()

	if boundaryTimer != nil {
		boundaryTimer.Stop()
		boundaryTimer = nil
	}
}

func scheduleBoundaryRefresh(schedule apiSchedule) {
	endAt, err := time.Parse(time.RFC3339, schedule.Current.EndsAt)
	if err != nil {
		return
	}

	delay := time.Until(endAt) + boundaryExtraDelay
	if delay < minBoundaryDelay {
		delay = minBoundaryDelay
	}

	boundaryMu.Lock()
	defer boundaryMu.Unlock()

	if boundaryTimer != nil {
		boundaryTimer.Stop()
	}
	boundaryTimer = time.AfterFunc(delay, func() {
		_ = refreshSchedule()
	})
}

func setOnlineState(schedule *apiSchedule) {
	stateMu.Lock()
	defer stateMu.Unlock()

	fetchedAt := time.Now().UTC()
	latestState = publicState{
		Data:      schedule,
		Online:    true,
		FetchedAt: &fetchedAt,
	}
}

func setOfflineState() {
	stateMu.Lock()
	defer stateMu.Unlock()

	latestState.Online = false
}

func getState() publicState {
	stateMu.RLock()
	defer stateMu.RUnlock()

	state := publicState{
		Online:    latestState.Online,
		FetchedAt: latestState.FetchedAt,
	}
	if latestState.Data != nil {
		dataCopy := *latestState.Data
		dataCopy.Upcoming = append([]mapData(nil), latestState.Data.Upcoming...)
		state.Data = &dataCopy
	}
	return state
}

func refreshSchedule() error {
	refreshMu.Lock()
	defer refreshMu.Unlock()

	ctx, cancel := context.WithTimeout(context.Background(), requestTimeout)
	defer cancel()

	schedule, err := fetchSchedule(ctx)
	if err != nil {
		setOfflineState()
		log.Printf("[Apex Rotation] %v", err)
		return err
	}

	setOnlineState(&schedule)
	scheduleBoundaryRefresh(schedule)
	return nil
}

func startPolling() {
	go func() {
		ticker := time.NewTicker(pollInterval)
		defer ticker.Stop()

		for range ticker.C {
			_ = refreshSchedule()
		}
	}()
}

func writeJSON(writer http.ResponseWriter, statusCode int, payload any) {
	writer.Header().Set("Cache-Control", "no-store")
	writer.Header().Set("Content-Type", "application/json; charset=utf-8")
	writer.WriteHeader(statusCode)
	_ = json.NewEncoder(writer).Encode(payload)
}

func serveIndex(writer http.ResponseWriter) {
	source, err := fs.ReadFile(staticFiles, "index.html")
	if err != nil {
		http.Error(writer, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	stateJSON, err := json.Marshal(getState())
	if err != nil {
		http.Error(writer, "Internal Server Error", http.StatusInternalServerError)
		return
	}

	safeState := strings.ReplaceAll(string(stateJSON), "<", "\\u003c")
	bootScript := `<script>window.__APEX_INITIAL_STATE__=` + safeState + `;</script>`
	html := strings.Replace(string(source), "</head>", bootScript+"</head>", 1)

	writer.Header().Set("Cache-Control", "no-store")
	writer.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = writer.Write([]byte(html))
}

func methodAllowed(writer http.ResponseWriter, request *http.Request) bool {
	if request.Method == http.MethodGet || request.Method == http.MethodHead {
		return true
	}
	writer.Header().Set("Allow", "GET, HEAD")
	http.Error(writer, "Method Not Allowed", http.StatusMethodNotAllowed)
	return false
}

func handler() http.Handler {
	staticHandler := http.FileServer(http.FS(staticFiles))

	return http.HandlerFunc(func(writer http.ResponseWriter, request *http.Request) {
		if !methodAllowed(writer, request) {
			return
		}

		switch request.URL.Path {
		case "/api/schedule":
			state := getState()
			if state.Data == nil {
				writeJSON(writer, http.StatusServiceUnavailable, state)
				return
			}
			writeJSON(writer, http.StatusOK, state)
		case "/healthz":
			state := getState()
			writeJSON(writer, http.StatusOK, map[string]bool{
				"online":  state.Online,
				"hasData": state.Data != nil,
			})
		case "/", "/index.html":
			serveIndex(writer)
		default:
			staticHandler.ServeHTTP(writer, request)
		}
	})
}

func main() {
	_ = refreshSchedule()
	startPolling()

	server := &http.Server{
		Addr:              ":" + strconv.Itoa(configuredPort()),
		Handler:           handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("Apex Rotation running at http://0.0.0.0:%d", configuredPort())
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
