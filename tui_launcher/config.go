package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
)

// Config is stored next to the executable (portable); override with --config or LAUNCHER_CONFIG.
type Config struct {
	DataDir    string `json:"data_dir,omitempty"`    // Luanti user data dir; empty = detected
	Command    string `json:"command,omitempty"`     // custom launch command (space separated); empty = detected
	ModsSource string `json:"mods_source,omitempty"` // folder whose subfolders are mods to copy into DataDir/mods
	GameSource string `json:"game_source,omitempty"` // optional folder copied to DataDir/games/<basename>
}

func configPath(flagPath string) string {
	if flagPath != "" {
		return flagPath
	}
	if p := os.Getenv("LAUNCHER_CONFIG"); p != "" {
		return p
	}
	// Portable: always next to the executable, never in ~/.config. A read-only folder is reported by saveConfig.
	exe, err := os.Executable()
	if err != nil {
		return "launcher.json"
	}
	return filepath.Join(filepath.Dir(exe), "launcher.json")
}

func loadConfig(path string) Config {
	var c Config
	if b, err := os.ReadFile(path); err == nil {
		_ = json.Unmarshal(b, &c)
	}
	return c
}

func saveConfig(path string, c Config) error {
	b, _ := json.MarshalIndent(c, "", "  ")
	if err := os.WriteFile(path, b, 0o644); err != nil {
		return fmt.Errorf("cannot save settings to %s (the launcher never writes elsewhere; move it to a writable folder or pass --config): %w", path, err)
	}
	return nil
}
