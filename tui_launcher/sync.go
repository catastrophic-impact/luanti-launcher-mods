package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

const manifestName = ".launcher-managed.json"

func copyFile(src, dst string, mode os.FileMode) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

// syncTree makes dst an exact copy of src (files with the same size+mtime are skipped, extra files removed).
func syncTree(src, dst string) (changed int, err error) {
	if err = os.MkdirAll(dst, 0o755); err != nil {
		return
	}
	want := map[string]bool{}
	ents, err := os.ReadDir(src)
	if err != nil {
		return
	}
	for _, e := range ents {
		s, d := filepath.Join(src, e.Name()), filepath.Join(dst, e.Name())
		want[e.Name()] = true
		if e.IsDir() {
			n, err2 := syncTree(s, d)
			changed += n
			if err2 != nil {
				return changed, err2
			}
			continue
		}
		si, err2 := os.Stat(s)
		if err2 != nil {
			return changed, err2
		}
		if di, err3 := os.Stat(d); err3 == nil && !di.IsDir() && di.Size() == si.Size() && di.ModTime().Equal(si.ModTime()) {
			continue
		}
		os.RemoveAll(d)
		if err2 = copyFile(s, d, si.Mode().Perm()); err2 != nil {
			return changed, err2
		}
		_ = os.Chtimes(d, si.ModTime(), si.ModTime())
		changed++
	}
	old, _ := os.ReadDir(dst)
	for _, e := range old {
		if !want[e.Name()] {
			os.RemoveAll(filepath.Join(dst, e.Name()))
			changed++
		}
	}
	return
}

// syncMods copies every mod folder in cfg.ModsSource into DataDir/mods and removes mods this launcher installed earlier
// that are gone from the source (other mods in that folder are never touched).
func syncMods(in Install, cfg Config) (string, error) {
	if cfg.ModsSource == "" {
		return "", fmt.Errorf("no mods source folder set (Settings)")
	}
	dst := filepath.Join(in.DataDir, "mods")
	ents, err := os.ReadDir(cfg.ModsSource)
	if err != nil {
		return "", err
	}
	var managed []string
	changed := 0
	for _, e := range ents {
		s := filepath.Join(cfg.ModsSource, e.Name())
		if !e.IsDir() || !isMod(s) && !exists(filepath.Join(s, "modpack.conf")) {
			continue
		}
		n, err := syncTree(s, filepath.Join(dst, e.Name()))
		if err != nil {
			return "", fmt.Errorf("%s: %w", e.Name(), err)
		}
		changed += n
		managed = append(managed, e.Name())
	}
	mf := filepath.Join(dst, manifestName)
	var prev []string
	if b, err := os.ReadFile(mf); err == nil {
		_ = json.Unmarshal(b, &prev)
	}
	now := map[string]bool{}
	for _, m := range managed {
		now[m] = true
	}
	removed := 0
	for _, p := range prev {
		if !now[p] {
			os.RemoveAll(filepath.Join(dst, p))
			removed++
		}
	}
	b, _ := json.Marshal(managed)
	_ = os.WriteFile(mf, b, 0o644)
	msg := fmt.Sprintf("%d mods synced (%d files changed, %d removed)", len(managed), changed, removed)
	if cfg.GameSource != "" {
		n, err := syncTree(cfg.GameSource, filepath.Join(in.DataDir, "games", filepath.Base(cfg.GameSource)))
		if err != nil {
			return msg, fmt.Errorf("game: %w", err)
		}
		msg += fmt.Sprintf("; game %s: %d files changed", filepath.Base(cfg.GameSource), n)
	}
	return msg, nil
}

// Folders the launcher manages inside a world (for mods like Wave Matrix and Skindependence).
type ManagedFolder struct{ Label, Rel, Exts string }

var managedFolders = []ManagedFolder{
	{"Wave Matrix music (.ogg)", "wavematrix", ".ogg"},
	{"Skins (.png)", "skindependence/skins", ".png"},
	{"Capes (.png)", "skindependence/capes", ".png"},
}

// addFiles copies one file, or every file with an allowed extension from a folder, into the world's managed folder.
func addFiles(world World, f ManagedFolder, from string) (string, error) {
	dst := filepath.Join(world.Path, filepath.FromSlash(f.Rel))
	if err := os.MkdirAll(dst, 0o755); err != nil {
		return "", err
	}
	st, err := os.Stat(from)
	if err != nil {
		return "", err
	}
	var files []string
	if st.IsDir() {
		ents, _ := os.ReadDir(from)
		for _, e := range ents {
			if !e.IsDir() && filepath.Ext(e.Name()) == f.Exts {
				files = append(files, filepath.Join(from, e.Name()))
			}
		}
	} else if filepath.Ext(from) == f.Exts {
		files = []string{from}
	} else {
		return "", fmt.Errorf("only %s files can go here", f.Exts)
	}
	for _, s := range files {
		if err := copyFile(s, filepath.Join(dst, filepath.Base(s)), 0o644); err != nil {
			return "", err
		}
	}
	return fmt.Sprintf("%d file(s) copied to %s", len(files), dst), nil
}

func listFolder(world World, f ManagedFolder) []string {
	var out []string
	ents, _ := os.ReadDir(filepath.Join(world.Path, filepath.FromSlash(f.Rel)))
	for _, e := range ents {
		if !e.IsDir() {
			out = append(out, e.Name())
		}
	}
	return out
}
