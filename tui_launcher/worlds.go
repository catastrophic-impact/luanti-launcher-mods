package main

import (
	"bufio"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// World is a folder under DataDir/worlds with a world.mt file.
type World struct {
	Name string
	Path string
}

func listWorlds(dataDir string) []World {
	var out []World
	ents, _ := os.ReadDir(filepath.Join(dataDir, "worlds"))
	for _, e := range ents {
		p := filepath.Join(dataDir, "worlds", e.Name())
		if exists(filepath.Join(p, "world.mt")) {
			out = append(out, World{e.Name(), p})
		}
	}
	return out
}

// worldMT keeps every line of world.mt so writing it back changes only load_mod_ lines.
type worldMT struct {
	path  string
	lines []string
}

func readWorldMT(world string) (*worldMT, error) {
	p := filepath.Join(world, "world.mt")
	f, err := os.Open(p)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	w := &worldMT{path: p}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		w.lines = append(w.lines, sc.Text())
	}
	return w, sc.Err()
}

func (w *worldMT) get(key string) (string, bool) {
	for _, l := range w.lines {
		k, v, ok := strings.Cut(l, "=")
		if ok && strings.TrimSpace(k) == key {
			return strings.TrimSpace(v), true
		}
	}
	return "", false
}

func (w *worldMT) set(key, val string) {
	for i, l := range w.lines {
		k, _, ok := strings.Cut(l, "=")
		if ok && strings.TrimSpace(k) == key {
			w.lines[i] = key + " = " + val
			return
		}
	}
	w.lines = append(w.lines, key+" = "+val)
}

func (w *worldMT) save() error {
	return os.WriteFile(w.path, []byte(strings.Join(w.lines, "\n")+"\n"), 0o644)
}

// modEnabled: Luanti treats a missing load_mod_<name> as disabled.
func (w *worldMT) modEnabled(name string) bool {
	v, ok := w.get("load_mod_" + name)
	return ok && v != "false" && v != ""
}

// modName reads name= from mod.conf, else the folder name.
func modName(dir string) string {
	if b, err := os.ReadFile(filepath.Join(dir, "mod.conf")); err == nil {
		for _, l := range strings.Split(string(b), "\n") {
			if k, v, ok := strings.Cut(l, "="); ok && strings.TrimSpace(k) == "name" {
				return strings.TrimSpace(v)
			}
		}
	}
	return filepath.Base(dir)
}

func isMod(dir string) bool {
	return exists(filepath.Join(dir, "mod.conf")) || exists(filepath.Join(dir, "init.lua"))
}

// listMods finds mods in DataDir/mods (one level of modpacks included).
func listMods(dataDir string) []string {
	seen := map[string]bool{}
	var scan func(dir string, depth int)
	scan = func(dir string, depth int) {
		ents, _ := os.ReadDir(dir)
		for _, e := range ents {
			if !e.IsDir() || strings.HasPrefix(e.Name(), ".") {
				continue
			}
			p := filepath.Join(dir, e.Name())
			switch {
			case isMod(p):
				seen[modName(p)] = true
			case depth < 2 && exists(filepath.Join(p, "modpack.conf")):
				scan(p, depth+1)
			}
		}
	}
	scan(filepath.Join(dataDir, "mods"), 0)
	var out []string
	for n := range seen {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}
