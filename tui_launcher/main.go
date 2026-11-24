package main

import (
	"flag"
	"fmt"
	"os"

	tea "github.com/charmbracelet/bubbletea"
	zone "github.com/lrstanley/bubblezone"
)

func main() {
	cfgFlag := flag.String("config", "", "config file (default: launcher.json next to the executable)")
	doSync := flag.Bool("sync", false, "sync mods into the Luanti data dir and exit")
	list := flag.Bool("info", false, "print the detected install, worlds and mods, then exit")
	flag.Parse()
	path := configPath(*cfgFlag)
	cfg := loadConfig(path)
	in, ok := detectInstall(cfg)
	if *list || *doSync {
		if !ok {
			fmt.Fprintln(os.Stderr, "no Luanti install found (set data_dir/command in", path+")")
			os.Exit(1)
		}
		if *doSync {
			msg, err := syncMods(in, cfg)
			fmt.Println(msg)
			if err != nil {
				fmt.Fprintln(os.Stderr, err)
				os.Exit(1)
			}
			return
		}
		fmt.Printf("config: %s\ninstall: %s %v\ndata: %s\n", path, in.Kind, in.Cmd, in.DataDir)
		for _, w := range listWorlds(in.DataDir) {
			fmt.Println("world:", w.Name)
		}
		fmt.Println("mods:", listMods(in.DataDir))
		return
	}
	zone.NewGlobal()
	m := newModel(path, cfg, in, ok)
	if _, err := tea.NewProgram(m, tea.WithAltScreen(), tea.WithMouseAllMotion()).Run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
