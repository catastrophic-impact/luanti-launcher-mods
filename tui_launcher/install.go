package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// Install describes how to run Luanti and where its user data lives.
type Install struct {
	Kind    string   // flatpak | native | custom
	DataDir string
	Cmd     []string
}

func exists(p string) bool { _, err := os.Stat(p); return err == nil }

func detectInstall(cfg Config) (Install, bool) {
	home, _ := os.UserHomeDir()
	var in Install
	switch {
	case cfg.Command != "":
		in = Install{Kind: "custom", Cmd: strings.Fields(cfg.Command)}
	default:
		found := false
		if fp, err := exec.LookPath("flatpak"); err == nil {
			if exec.Command(fp, "info", "org.luanti.luanti").Run() == nil {
				in = Install{Kind: "flatpak", Cmd: []string{fp, "run", "org.luanti.luanti"},
					DataDir: filepath.Join(home, ".var/app/org.luanti.luanti/.minetest")}
				found = true
			}
		}
		if !found {
			for _, name := range []string{"luanti", "minetest"} {
				if p, err := exec.LookPath(name); err == nil {
					in = Install{Kind: "native", Cmd: []string{p}}
					found = true
					break
				}
			}
		}
		if !found {
			return Install{}, false
		}
	}
	if cfg.DataDir != "" {
		in.DataDir = cfg.DataDir
	}
	if in.DataDir == "" { // native / custom: Luanti's own search order
		for _, d := range []string{filepath.Join(home, ".minetest"), filepath.Join(home, ".luanti"), filepath.Join(home, ".local/share/luanti")} {
			if exists(d) {
				in.DataDir = d
				break
			}
		}
		if in.DataDir == "" {
			in.DataDir = filepath.Join(home, ".minetest")
		}
	}
	return in, true
}
