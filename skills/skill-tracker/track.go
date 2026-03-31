// Hook binary for skill-tracker.
// Handles two hook events:
//   - UserPromptSubmit — detects /skill-name prompts, opens a token bracket
//   - Stop             — closes the last open bracket, writes stats to counts.json
//
// Token attribution: we record the transcript byte offset when a skill prompt
// is submitted. At Stop, we sum all assistant-message tokens from that offset
// forward, capturing only the tokens Claude spent executing the skill.
//
// Overhead separation: we also record the cache_read_tokens from the last
// assistant message *before* the skill was invoked as a per-turn baseline.
// Net cost = raw cost - (turns × baseline_cache_read × $0.30/MTok).
package main

import (
	"bufio"
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// ── hook event ────────────────────────────────────────────────────────────────

type HookEvent struct {
	HookEventName  string `json:"hook_event_name"`
	SessionID      string `json:"session_id"`
	TranscriptPath string `json:"transcript_path"`
	Prompt         string `json:"prompt"`
}

// ── per-session state (written to /tmp) ───────────────────────────────────────

type SessionState struct {
	TranscriptPath        string `json:"transcript_path"`
	LastSkill             string `json:"last_skill"`
	LastTranscriptPos     int64  `json:"last_transcript_pos"`
	StartTimeUnixMs       int64  `json:"start_time_unix_ms"`
	BaselineCacheReadToks int    `json:"baseline_cache_read_tokens"`
}

// ── persistent counts ─────────────────────────────────────────────────────────

type SkillStats struct {
	Uses                int     `json:"uses"`
	InputTokens         int     `json:"input_tokens"`
	OutputTokens        int     `json:"output_tokens"`
	CacheCreationTokens int     `json:"cache_creation_tokens"`
	CacheReadTokens     int     `json:"cache_read_tokens"`
	EstimatedCostUSD    float64 `json:"estimated_cost_usd"`
	OverheadCostUSD     float64 `json:"overhead_cost_usd"`
	TotalMs             int64   `json:"total_ms"`
}

// ── transcript entry (only the fields we care about) ─────────────────────────

type TranscriptEntry struct {
	Type    string `json:"type"`
	Message *struct {
		Usage *struct {
			InputTokens              int `json:"input_tokens"`
			OutputTokens             int `json:"output_tokens"`
			CacheCreationInputTokens int `json:"cache_creation_input_tokens"`
			CacheReadInputTokens     int `json:"cache_read_input_tokens"`
		} `json:"usage"`
	} `json:"message"`
}

// ── paths ─────────────────────────────────────────────────────────────────────

var trackerDir = filepath.Dir(os.Args[0]) // config.json and counts.json live alongside the binary
var skillsDir = filepath.Join(os.Getenv("HOME"), ".claude", "skills")
var countsPath = filepath.Join(trackerDir, "counts.json")
var stateDir = filepath.Join(os.TempDir(), "skill-tracker")

// ── config ────────────────────────────────────────────────────────────────────

type Config struct {
	Ignore []string `json:"ignore"`
}

func loadConfig() Config {
	b, err := os.ReadFile(filepath.Join(trackerDir, "config.json"))
	if err != nil {
		return Config{}
	}
	var c Config
	json.Unmarshal(b, &c)
	return c
}

var config = loadConfig()

func stateFilePath(sessionID string) string {
	return filepath.Join(stateDir, sessionID+".json")
}

// ── skill detection ───────────────────────────────────────────────────────────

var slashCmd = regexp.MustCompile(`^/(\w[\w-]*)`)

func extractSkillName(prompt string) string {
	m := slashCmd.FindStringSubmatch(strings.TrimSpace(prompt))
	if m == nil {
		return ""
	}
	name := m[1]
	for _, ignored := range config.Ignore {
		if name == ignored {
			return ""
		}
	}
	info, err := os.Stat(filepath.Join(skillsDir, name))
	if err != nil || !info.IsDir() {
		return ""
	}
	return name
}

// ── counts helpers ────────────────────────────────────────────────────────────

func loadCounts() map[string]SkillStats {
	out := map[string]SkillStats{}
	b, err := os.ReadFile(countsPath)
	if err != nil {
		return out
	}
	json.Unmarshal(b, &out)
	return out
}

func saveCounts(data map[string]SkillStats) {
	b, _ := json.MarshalIndent(data, "", "  ")
	os.WriteFile(countsPath, append(b, '\n'), 0644)
}

// ── session state helpers ─────────────────────────────────────────────────────

func loadState(sessionID string) *SessionState {
	b, err := os.ReadFile(stateFilePath(sessionID))
	if err != nil {
		return nil
	}
	var s SessionState
	json.Unmarshal(b, &s)
	return &s
}

func saveState(sessionID string, s *SessionState) {
	os.MkdirAll(stateDir, 0755)
	b, _ := json.MarshalIndent(s, "", "  ")
	os.WriteFile(stateFilePath(sessionID), b, 0644)
}

func deleteState(sessionID string) {
	os.Remove(stateFilePath(sessionID))
}

// ── token counting ────────────────────────────────────────────────────────────

type tokenTotals struct {
	input, output, cacheCreate, cacheRead int
	assistantTurns                        int
}

// lastAssistantCacheReads scans the transcript up to endPos and returns the
// cache_read_input_tokens from the final assistant message found.
func lastAssistantCacheReads(transcriptPath string, endPos int64) int {
	f, err := os.Open(transcriptPath)
	if err != nil {
		return 0
	}
	defer f.Close()

	var last int
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 2*1024*1024), 2*1024*1024)
	var pos int64
	for sc.Scan() {
		line := sc.Bytes()
		pos += int64(len(line)) + 1 // +1 for newline
		if pos > endPos {
			break
		}
		var e TranscriptEntry
		if json.Unmarshal(line, &e) != nil {
			continue
		}
		if e.Type == "assistant" && e.Message != nil && e.Message.Usage != nil {
			last = e.Message.Usage.CacheReadInputTokens
		}
	}
	return last
}

func sumTokensSince(transcriptPath string, fromPos int64) tokenTotals {
	f, err := os.Open(transcriptPath)
	if err != nil {
		return tokenTotals{}
	}
	defer f.Close()
	f.Seek(fromPos, 0)

	var t tokenTotals
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 2*1024*1024), 2*1024*1024)
	for sc.Scan() {
		var e TranscriptEntry
		if json.Unmarshal(sc.Bytes(), &e) != nil {
			continue
		}
		if e.Type == "assistant" && e.Message != nil && e.Message.Usage != nil {
			u := e.Message.Usage
			t.input += u.InputTokens
			t.output += u.OutputTokens
			t.cacheCreate += u.CacheCreationInputTokens
			t.cacheRead += u.CacheReadInputTokens
			t.assistantTurns++
		}
	}
	return t
}

func transcriptSize(path string) int64 {
	info, err := os.Stat(path)
	if err != nil {
		return 0
	}
	return info.Size()
}

// estimateCostUSD uses claude-sonnet-4-6 pricing (per-token, rates captured 2026-03).
// Input $3/MTok, Output $15/MTok, Cache write $3.75/MTok, Cache read $0.30/MTok.
// Update these constants when pricing changes.
func estimateCostUSD(t tokenTotals) float64 {
	const M = 1_000_000.0
	return float64(t.input)*3.0/M +
		float64(t.output)*15.0/M +
		float64(t.cacheCreate)*3.75/M +
		float64(t.cacheRead)*0.30/M
}

func overheadCostUSD(baselineCacheReadToks int, turns int) float64 {
	const M = 1_000_000.0
	return float64(baselineCacheReadToks) * float64(turns) * 0.30 / M
}

// ── event handlers ────────────────────────────────────────────────────────────

func closeLastBracket(sessionID string, nowMs int64, counts map[string]SkillStats) {
	state := loadState(sessionID)
	if state == nil || state.LastSkill == "" {
		return
	}
	t := sumTokensSince(state.TranscriptPath, state.LastTranscriptPos)
	s := counts[state.LastSkill]
	s.InputTokens += t.input
	s.OutputTokens += t.output
	s.CacheCreationTokens += t.cacheCreate
	s.CacheReadTokens += t.cacheRead
	s.EstimatedCostUSD += estimateCostUSD(t)
	s.OverheadCostUSD += overheadCostUSD(state.BaselineCacheReadToks, t.assistantTurns)
	if state.StartTimeUnixMs > 0 {
		s.TotalMs += nowMs - state.StartTimeUnixMs
	}
	counts[state.LastSkill] = s
}

func handleUserPromptSubmit(event HookEvent) {
	skillName := extractSkillName(event.Prompt)
	if skillName == "" {
		return
	}

	nowMs := time.Now().UnixMilli()
	counts := loadCounts()

	// Close previous skill's bracket if any (e.g. two skills in one session).
	closeLastBracket(event.SessionID, nowMs, counts)

	// Sample the baseline per-turn overhead from the last assistant message
	// before this skill invocation.
	currentPos := transcriptSize(event.TranscriptPath)
	baseline := lastAssistantCacheReads(event.TranscriptPath, currentPos)

	// Increment use count and open a new bracket.
	s := counts[skillName]
	s.Uses++
	counts[skillName] = s
	saveCounts(counts)

	saveState(event.SessionID, &SessionState{
		TranscriptPath:        event.TranscriptPath,
		LastSkill:             skillName,
		LastTranscriptPos:     currentPos,
		StartTimeUnixMs:       nowMs,
		BaselineCacheReadToks: baseline,
	})
}

func handleStop(event HookEvent) {
	nowMs := time.Now().UnixMilli()
	counts := loadCounts()
	closeLastBracket(event.SessionID, nowMs, counts)
	saveCounts(counts)
	deleteState(event.SessionID)
}

// ── main ──────────────────────────────────────────────────────────────────────

func main() {
	var event HookEvent
	if err := json.NewDecoder(os.Stdin).Decode(&event); err != nil {
		os.Exit(0)
	}
	switch event.HookEventName {
	case "UserPromptSubmit":
		handleUserPromptSubmit(event)
	case "Stop":
		handleStop(event)
	}
}
