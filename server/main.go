package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

type mapData struct {
	Key             string `json:"key"`
	Slug            string `json:"slug"`
	Name            string `json:"name"`
	StartsAt        string `json:"starts_at"`
	EndsAt          string `json:"ends_at"`
	DurationMinutes int    `json:"duration_minutes"`
	IsCurrent       bool   `json:"is_current"`
	Placeholder     bool   `json:"placeholder,omitempty"`
}

type apiSchedule struct {
	Current      mapData   `json:"current"`
	Next         mapData   `json:"next"`
	Upcoming     []mapData `json:"upcoming"`
	CycleMinutes int       `json:"cycle_minutes"`
}

type publicState struct {
	Data      *apiSchedule `json:"data"`
	Online    bool         `json:"online"`
	FetchedAt *time.Time   `json:"fetchedAt"`
}

type apexStatusResponse struct {
	Ranked apexStatusMode `json:"ranked"`
}

type apexStatusMode struct {
	Current apexStatusMap `json:"current"`
	Next    apexStatusMap `json:"next"`
}

type apexStatusMap struct {
	Start             int64  `json:"start"`
	End               int64  `json:"end"`
	Map               string `json:"map"`
	Code              string `json:"code"`
	DurationInMinutes int    `json:"DurationInMinutes"`
}

type catalogFile struct {
	Maps []catalogMap `json:"maps"`
}

type catalogMap struct {
	Name            string   `json:"name"`
	Slug            string   `json:"slug"`
	ApexStatusCodes []string `json:"apexStatusCodes"`
	Aliases         []string `json:"aliases"`
}

type mapSnapshot struct {
	ID   string `json:"id"`
	Key  string `json:"key"`
	Slug string `json:"slug"`
	Name string `json:"name"`
}

type learnedTransition struct {
	From     mapSnapshot `json:"from"`
	To       mapSnapshot `json:"to"`
	LastSeen string      `json:"last_seen"`
}

type rotationMemory struct {
	Transitions map[string]learnedTransition `json:"transitions"`
}

var (
	stateMu          sync.RWMutex
	refreshMu        sync.Mutex
	boundaryMu       sync.Mutex
	memoryMu         sync.Mutex
	boundaryTimer    *time.Timer
	latestState      = publicState{}
	mapCatalogJSON   string
	mapCatalogLookup = map[string]catalogMap{}
	publicDir        string
	rotationState    = rotationMemory{Transitions: map[string]learnedTransition{}}
	stateFilePath    string
)

func resolvePublicDir() (string, error) {
	executable, err := os.Executable()
	if err != nil {
		return "", err
	}

	executableDir := filepath.Dir(executable)
	candidates := []string{
		filepath.Join(".", publicDirectoryName),
		filepath.Join(".", "..", publicDirectoryName),
		filepath.Join(executableDir, publicDirectoryName),
		filepath.Join(executableDir, "..", publicDirectoryName),
	}

	for _, candidate := range candidates {
		absolute, err := filepath.Abs(candidate)
		if err != nil {
			continue
		}

		info, err := os.Stat(absolute)
		if err == nil && info.IsDir() {
			return absolute, nil
		}
	}

	return "", fmt.Errorf("找不到 %s 目录", publicDirectoryName)
}

func normalizeLookupValue(value string) string {
	value = strings.ToLower(strings.TrimSpace(value))
	value = strings.ReplaceAll(value, "'", "")
	value = strings.ReplaceAll(value, "’", "")

	var builder strings.Builder
	lastSeparator := false
	for _, char := range value {
		isLetter := char >= 'a' && char <= 'z'
		isNumber := char >= '0' && char <= '9'
		if isLetter || isNumber {
			builder.WriteRune(char)
			lastSeparator = false
			continue
		}

		if builder.Len() > 0 && !lastSeparator {
			builder.WriteByte('_')
			lastSeparator = true
		}
	}

	return strings.Trim(builder.String(), "_")
}

func slugFromName(value string) string {
	return strings.ReplaceAll(normalizeLookupValue(value), "_", "-")
}

func addCatalogLookup(lookup map[string]catalogMap, key string, item catalogMap) {
	normalized := normalizeLookupValue(key)
	if normalized != "" {
		lookup[normalized] = item
	}
}

func indexMapCatalog(catalog []byte) error {
	var payload catalogFile
	if err := json.Unmarshal(catalog, &payload); err != nil {
		return err
	}

	lookup := map[string]catalogMap{}
	for _, item := range payload.Maps {
		if item.Name == "" || item.Slug == "" {
			continue
		}

		addCatalogLookup(lookup, item.Name, item)
		addCatalogLookup(lookup, item.Slug, item)
		for _, code := range item.ApexStatusCodes {
			addCatalogLookup(lookup, code, item)
		}
		for _, alias := range item.Aliases {
			addCatalogLookup(lookup, alias, item)
		}
	}

	mapCatalogLookup = lookup
	return nil
}

func findCatalogMap(name string, code string) (catalogMap, bool) {
	for _, value := range []string{code, name, slugFromName(name)} {
		if item, ok := mapCatalogLookup[normalizeLookupValue(value)]; ok {
			return item, true
		}
	}
	return catalogMap{}, false
}

func apexStatusAPIKey() (string, error) {
	apiKey := strings.TrimSpace(os.Getenv(apexStatusAPIKeyEnv))
	if apiKey == "" || strings.EqualFold(apiKey, "YOUR_APEX_LEGENDS_STATUS_API_KEY") {
		return "", fmt.Errorf("%s 未配置", apexStatusAPIKeyEnv)
	}
	return apiKey, nil
}

func apexStatusRequestURL(apiKey string) (string, error) {
	endpoint, err := url.Parse(apexStatusAPIURL)
	if err != nil {
		return "", err
	}

	query := endpoint.Query()
	query.Set("auth", apiKey)
	query.Set("version", "2")
	endpoint.RawQuery = query.Encode()
	return endpoint.String(), nil
}

func normalizeApexStatusMap(item apexStatusMap, isCurrent bool) (mapData, error) {
	name := strings.TrimSpace(item.Map)
	code := strings.TrimSpace(item.Code)
	if name == "" {
		return mapData{}, fmt.Errorf("API 未返回地图名称")
	}
	if item.Start <= 0 || item.End <= item.Start {
		return mapData{}, fmt.Errorf("API 返回的轮换时间无效")
	}

	start := time.Unix(item.Start, 0).UTC()
	end := time.Unix(item.End, 0).UTC()
	durationMinutes := item.DurationInMinutes
	if durationMinutes <= 0 {
		durationMinutes = int(end.Sub(start).Minutes())
	}
	if durationMinutes <= 0 {
		return mapData{}, fmt.Errorf("API 返回的轮换时长无效")
	}

	slug := slugFromName(name)
	if catalogItem, ok := findCatalogMap(name, code); ok {
		name = catalogItem.Name
		slug = catalogItem.Slug
	}
	key := code
	if key == "" {
		key = slug
	}

	return mapData{
		Key:             key,
		Slug:            slug,
		Name:            name,
		StartsAt:        start.Format(time.RFC3339),
		EndsAt:          end.Format(time.RFC3339),
		DurationMinutes: durationMinutes,
		IsCurrent:       isCurrent,
	}, nil
}

func placeholderMap() mapData {
	return mapData{
		Name:        "--",
		Placeholder: true,
	}
}

func mapIdentity(item mapData) string {
	for _, value := range []string{item.Slug, item.Key, item.Name} {
		if normalized := normalizeLookupValue(value); normalized != "" {
			return normalized
		}
	}
	return ""
}

func snapshotIdentity(snapshot mapSnapshot) string {
	for _, value := range []string{snapshot.ID, snapshot.Slug, snapshot.Key, snapshot.Name} {
		if normalized := normalizeLookupValue(value); normalized != "" {
			return normalized
		}
	}
	return ""
}

func snapshotMap(item mapData) mapSnapshot {
	return mapSnapshot{
		ID:   mapIdentity(item),
		Key:  item.Key,
		Slug: item.Slug,
		Name: item.Name,
	}
}

func transitionFresh(transition learnedTransition, now time.Time) bool {
	lastSeen, err := time.Parse(time.RFC3339, transition.LastSeen)
	if err != nil {
		return false
	}
	age := now.Sub(lastSeen)
	return age >= 0 && age <= transitionMaxAge
}

func pruneRotationMemoryLocked(now time.Time) {
	for id, transition := range rotationState.Transitions {
		if !transitionFresh(transition, now) {
			delete(rotationState.Transitions, id)
		}
	}
}

func saveRotationMemoryLocked() error {
	if stateFilePath == "" {
		return nil
	}
	if err := os.MkdirAll(filepath.Dir(stateFilePath), 0700); err != nil {
		return err
	}

	payload, err := json.MarshalIndent(rotationState, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(stateFilePath, payload, 0600)
}

func loadRotationMemory() {
	stateFilePath = filepath.Join(filepath.Dir(publicDir), stateDirectoryName, stateFileName)

	payload, err := os.ReadFile(stateFilePath)
	if err != nil {
		if !os.IsNotExist(err) {
			log.Printf("[Apex Rotation] 读取轮换记忆失败: %v", err)
		}
		return
	}

	var memory rotationMemory
	if err := json.Unmarshal(payload, &memory); err != nil {
		log.Printf("[Apex Rotation] 轮换记忆格式无效: %v", err)
		return
	}
	if memory.Transitions == nil {
		memory.Transitions = map[string]learnedTransition{}
	}

	memoryMu.Lock()
	rotationState = memory
	pruneRotationMemoryLocked(time.Now().UTC())
	memoryMu.Unlock()
}

func learnTransition(current mapData, next mapData) {
	fromID := mapIdentity(current)
	toID := mapIdentity(next)
	if fromID == "" || toID == "" || fromID == toID {
		return
	}

	now := time.Now().UTC()
	transition := learnedTransition{
		From:     snapshotMap(current),
		To:       snapshotMap(next),
		LastSeen: now.Format(time.RFC3339),
	}

	memoryMu.Lock()
	defer memoryMu.Unlock()

	if rotationState.Transitions == nil {
		rotationState.Transitions = map[string]learnedTransition{}
	}

	if existing, ok := rotationState.Transitions[fromID]; ok && snapshotIdentity(existing.To) == toID {
		if lastSeen, err := time.Parse(time.RFC3339, existing.LastSeen); err == nil && now.Sub(lastSeen) < memoryWriteInterval {
			rotationState.Transitions[fromID] = transition
			return
		}
	}

	rotationState.Transitions[fromID] = transition
	pruneRotationMemoryLocked(now)
	if err := saveRotationMemoryLocked(); err != nil {
		log.Printf("[Apex Rotation] 保存轮换记忆失败: %v", err)
	}
}

func mapDuration(item mapData) time.Duration {
	if item.DurationMinutes > 0 {
		return time.Duration(item.DurationMinutes) * time.Minute
	}

	startsAt, startErr := time.Parse(time.RFC3339, item.StartsAt)
	endsAt, endErr := time.Parse(time.RFC3339, item.EndsAt)
	if startErr == nil && endErr == nil && endsAt.After(startsAt) {
		return endsAt.Sub(startsAt)
	}
	return 0
}

func inferThirdMap(current mapData, next mapData) (mapData, bool) {
	currentID := mapIdentity(current)
	nextID := mapIdentity(next)
	if currentID == "" || nextID == "" {
		return mapData{}, false
	}

	now := time.Now().UTC()
	memoryMu.Lock()
	defer memoryMu.Unlock()

	pruneRotationMemoryLocked(now)
	nextTransition, ok := rotationState.Transitions[nextID]
	if !ok || !transitionFresh(nextTransition, now) {
		return mapData{}, false
	}

	thirdSnapshot := nextTransition.To
	thirdID := snapshotIdentity(thirdSnapshot)
	if thirdID == "" || thirdID == currentID || thirdID == nextID || thirdSnapshot.Name == "" {
		return mapData{}, false
	}

	closingTransition, ok := rotationState.Transitions[thirdID]
	if !ok || !transitionFresh(closingTransition, now) || snapshotIdentity(closingTransition.To) != currentID {
		return mapData{}, false
	}

	startsAt, err := time.Parse(time.RFC3339, next.EndsAt)
	if err != nil {
		return mapData{}, false
	}
	duration := mapDuration(next)
	if duration <= 0 {
		duration = mapDuration(current)
	}
	if duration <= 0 {
		return mapData{}, false
	}

	return mapData{
		Key:             thirdSnapshot.Key,
		Slug:            thirdSnapshot.Slug,
		Name:            thirdSnapshot.Name,
		StartsAt:        startsAt.Format(time.RFC3339),
		EndsAt:          startsAt.Add(duration).Format(time.RFC3339),
		DurationMinutes: int(duration.Minutes()),
		IsCurrent:       false,
	}, true
}

func normalizeSchedule(payload apexStatusResponse) (apiSchedule, error) {
	current, err := normalizeApexStatusMap(payload.Ranked.Current, true)
	if err != nil {
		return apiSchedule{}, err
	}
	next, err := normalizeApexStatusMap(payload.Ranked.Next, false)
	if err != nil {
		return apiSchedule{}, err
	}

	learnTransition(current, next)
	third := placeholderMap()
	if inferred, ok := inferThirdMap(current, next); ok {
		third = inferred
	}

	return apiSchedule{
		Current:      current,
		Next:         next,
		Upcoming:     []mapData{current, next, third},
		CycleMinutes: current.DurationMinutes,
	}, nil
}

func fetchSchedule(ctx context.Context) (apiSchedule, error) {
	apiKey, err := apexStatusAPIKey()
	if err != nil {
		return apiSchedule{}, err
	}
	requestURL, err := apexStatusRequestURL(apiKey)
	if err != nil {
		return apiSchedule{}, err
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, requestURL, nil)
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

	var payload apexStatusResponse
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
		resetBoundaryTimer()
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
	source, err := os.ReadFile(filepath.Join(publicDir, "index.html"))
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
	bootScript := `<script>window.__APEX_INITIAL_STATE__=` + safeState +
		`;window.__APEX_MAP_CATALOG__=` + mapCatalogJSON + `;</script>`
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
	staticHandler := http.FileServer(http.Dir(publicDir))

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
			if strings.HasPrefix(request.URL.Path, "/image/") &&
				(strings.HasSuffix(request.URL.Path, ".webp") ||
					strings.HasSuffix(request.URL.Path, ".png") ||
					strings.HasSuffix(request.URL.Path, ".ico")) {
				writer.Header().Set("Cache-Control", "public, max-age=2592000")
				if strings.HasSuffix(request.URL.Path, ".webp") {
					writer.Header().Set("Content-Type", "image/webp")
				}
			}
			staticHandler.ServeHTTP(writer, request)
		}
	})
}

func main() {
	var err error
	publicDir, err = resolvePublicDir()
	if err != nil {
		log.Fatal(err)
	}

	catalog, err := os.ReadFile(filepath.Join(publicDir, "image", "maps.json"))
	if err != nil || !json.Valid(catalog) || indexMapCatalog(catalog) != nil {
		log.Fatal("地图资源清单无效")
	}
	mapCatalogJSON = strings.ReplaceAll(string(catalog), "<", "\\u003c")
	loadRotationMemory()

	_ = refreshSchedule()
	startPolling()

	server := &http.Server{
		Addr:              fmt.Sprintf(":%d", defaultPort),
		Handler:           handler(),
		ReadHeaderTimeout: 5 * time.Second,
	}

	log.Printf("Apex Rotation running at http://0.0.0.0:%d", defaultPort)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatal(err)
	}
}
