package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestWorldMTRoundTrip(t *testing.T) {
	d := t.TempDir()
	os.WriteFile(filepath.Join(d, "world.mt"), []byte("gameid = mineclonia\nload_mod_a = true\nload_mod_b = false\nbackend = sqlite3\n"), 0o644)
	w, err := readWorldMT(d)
	if err != nil {
		t.Fatal(err)
	}
	if !w.modEnabled("a") || w.modEnabled("b") || w.modEnabled("zzz") {
		t.Fatal("enabled flags wrong")
	}
	w.set("load_mod_b", "true")
	w.set("load_mod_c", "true")
	if err := w.save(); err != nil {
		t.Fatal(err)
	}
	b, _ := os.ReadFile(filepath.Join(d, "world.mt"))
	want := "gameid = mineclonia\nload_mod_a = true\nload_mod_b = true\nbackend = sqlite3\nload_mod_c = true\n"
	if string(b) != want {
		t.Fatalf("got %q", b)
	}
}

func TestAddFilesAndSync(t *testing.T) {
	d := t.TempDir()
	src := filepath.Join(d, "src")
	os.MkdirAll(src, 0o755)
	os.WriteFile(filepath.Join(src, "a.ogg"), []byte("x"), 0o644)
	os.WriteFile(filepath.Join(src, "b.txt"), []byte("x"), 0o644)
	w := World{"w", filepath.Join(d, "world")}
	os.MkdirAll(w.Path, 0o755)
	msg, err := addFiles(w, managedFolders[0], src)
	if err != nil || len(listFolder(w, managedFolders[0])) != 1 {
		t.Fatal(msg, err)
	}
	if _, err := addFiles(w, managedFolders[0], filepath.Join(src, "b.txt")); err == nil {
		t.Fatal("wrong extension accepted")
	}
	// syncTree removes extras
	os.WriteFile(filepath.Join(d, "dst_extra"), nil, 0o644)
	dst := filepath.Join(d, "dst")
	os.MkdirAll(dst, 0o755)
	os.WriteFile(filepath.Join(dst, "old"), nil, 0o644)
	if _, err := syncTree(src, dst); err != nil {
		t.Fatal(err)
	}
	if exists(filepath.Join(dst, "old")) || !exists(filepath.Join(dst, "a.ogg")) {
		t.Fatal("sync did not mirror")
	}
}
