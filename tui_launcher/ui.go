package main

import (
	"fmt"
	"os/exec"
	"strings"

	"github.com/charmbracelet/bubbles/textinput"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	zone "github.com/lrstanley/bubblezone"
)

var tabNames = []string{"Play", "Mods", "Folders", "Sync", "Settings"}

const (
	tabPlay = iota
	tabMods
	tabFolders
	tabSync
	tabSettings
)

// Palette (works on dark and light terminals: only mid-tones).
var (
	cAccent = lipgloss.Color("86")
	cPrim   = lipgloss.Color("63")
	cText   = lipgloss.Color("252")
	cDim    = lipgloss.Color("244")
	cLine   = lipgloss.Color("240")
	cErr    = lipgloss.Color("203")
	cOk     = lipgloss.Color("114")
)

type editKind int

const (
	editNone editKind = iota
	editFolder
	editSetting
)

type model struct {
	cfgPath string
	cfg     Config
	in      Install
	found   bool

	w, h   int
	tab    int
	hover  string
	reg    *[]string // click zones registered by the last render (for hover detection)
	worlds []World
	wi     int // selected world
	mods   []string
	mt     *worldMT
	mi     int // mod cursor
	moff   int // mod scroll offset
	status string
	isErr  bool

	edit    editKind
	editIdx int
	input   textinput.Model
}

func newModel(path string, cfg Config, in Install, found bool) model {
	ti := textinput.New()
	ti.CharLimit = 500
	ti.Width = 60
	ti.Prompt = "> "
	m := model{cfgPath: path, cfg: cfg, in: in, found: found, input: ti, reg: &[]string{}, w: 100, h: 30}
	m.reload()
	return m
}

func (m *model) reload() {
	m.worlds = listWorlds(m.in.DataDir)
	if m.wi >= len(m.worlds) {
		m.wi = 0
	}
	m.mods, m.mt, m.mi, m.moff = nil, nil, 0, 0
	if m.tab == tabMods && len(m.worlds) > 0 {
		m.mods = listMods(m.in.DataDir)
		if mt, err := readWorldMT(m.worlds[m.wi].Path); err == nil {
			m.mt = mt
		}
	}
}

func (m *model) say(s string, err error) {
	if err != nil {
		m.status, m.isErr = s+err.Error(), true
	} else {
		m.status, m.isErr = s, false
	}
}

func (m model) Init() tea.Cmd { return nil }

type launched struct{ err error }

func (m model) launch(extra ...string) tea.Cmd {
	if len(m.in.Cmd) == 0 {
		return nil
	}
	c := exec.Command(m.in.Cmd[0], append(append([]string{}, m.in.Cmd[1:]...), extra...)...)
	return tea.ExecProcess(c, func(err error) tea.Msg { return launched{err} })
}

// ---- actions --------------------------------------------------------------------------------

func (m model) world() (World, bool) {
	if m.wi < len(m.worlds) {
		return m.worlds[m.wi], true
	}
	return World{}, false
}

func (m model) activate(id string) (tea.Model, tea.Cmd) {
	var n int
	switch {
	case id == "quit":
		return m, tea.Quit
	case sscan(id, "tab:", &n):
		m.tab, m.status = n, ""
		m.reload()
	case sscan(id, "world:", &n):
		m.wi = n
		m.reload()
	case id == "prevw" || id == "nextw":
		if len(m.worlds) > 0 {
			d := 1
			if id == "prevw" {
				d = len(m.worlds) - 1
			}
			m.wi = (m.wi + d) % len(m.worlds)
			m.reload()
		}
	case id == "launch":
		if !m.found {
			m.say("No Luanti install found: set the data folder or command in Settings.", nil)
			m.isErr = true
			return m, nil
		}
		return m, m.launch()
	case id == "launchworld":
		w, ok := m.world()
		if !ok || !m.found {
			m.say("Nothing to launch: pick a world (and make sure Luanti is found).", nil)
			m.isErr = true
			return m, nil
		}
		args := []string{"--go", "--world", w.Path}
		if mt, err := readWorldMT(w.Path); err == nil {
			if gid, ok := mt.get("gameid"); ok {
				args = append(args, "--gameid", gid)
			}
		}
		return m, m.launch(args...)
	case sscan(id, "mod:", &n):
		if m.mt != nil && n < len(m.mods) {
			m.mi = n
			name := m.mods[n]
			m.mt.set("load_mod_"+name, fmt.Sprint(!m.mt.modEnabled(name)))
			m.say("", m.mt.save())
		}
	case id == "allon" || id == "alloff":
		if m.mt != nil {
			for _, name := range m.mods {
				m.mt.set("load_mod_"+name, fmt.Sprint(id == "allon"))
			}
			m.say("", m.mt.save())
		}
	case sscan(id, "folder:", &n):
		if _, ok := m.world(); ok {
			m.startEdit(editFolder, n, "")
		}
	case id == "sync":
		if !m.found {
			m.say("No Luanti install found: set the data folder or command in Settings.", nil)
			m.isErr = true
			return m, nil
		}
		msg, err := syncMods(m.in, m.cfg)
		m.say(msg, err)
		m.reload()
	case sscan(id, "set:", &n):
		m.startEdit(editSetting, n, []string{m.cfg.ModsSource, m.cfg.DataDir, m.cfg.Command, m.cfg.GameSource}[n])
	case id == "save":
		return m.finishEdit()
	case id == "cancel":
		m.edit = editNone
		m.input.Blur()
	}
	return m, nil
}

func sscan(id, prefix string, n *int) bool {
	if !strings.HasPrefix(id, prefix) {
		return false
	}
	_, err := fmt.Sscanf(id[len(prefix):], "%d", n)
	return err == nil
}

func (m *model) startEdit(k editKind, idx int, val string) {
	m.edit, m.editIdx = k, idx
	m.input.SetValue(val)
	m.input.CursorEnd()
	m.input.Focus()
	if k == editFolder {
		m.input.Placeholder = "path to a file or a folder of " + managedFolders[idx].Exts + " files"
	} else {
		m.input.Placeholder = "(empty = automatic)"
	}
}

func (m model) finishEdit() (tea.Model, tea.Cmd) {
	v := strings.TrimSpace(m.input.Value())
	k, idx := m.edit, m.editIdx
	m.edit = editNone
	m.input.Blur()
	if k == editFolder {
		w, _ := m.world()
		msg, err := addFiles(w, managedFolders[idx], v)
		m.say(msg, err)
		return m, nil
	}
	switch idx {
	case 0:
		m.cfg.ModsSource = v
	case 1:
		m.cfg.DataDir = v
	case 2:
		m.cfg.Command = v
	case 3:
		m.cfg.GameSource = v
	}
	if err := saveConfig(m.cfgPath, m.cfg); err != nil {
		m.say("", err)
		return m, nil
	}
	m.in, m.found = detectInstall(m.cfg)
	m.reload()
	m.say("Saved.", nil)
	return m, nil
}

// ---- input ----------------------------------------------------------------------------------

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.w, m.h = msg.Width, msg.Height
	case launched:
		if msg.err != nil {
			m.say("Luanti exited with an error: ", msg.err)
		} else {
			m.say("Luanti closed.", nil)
		}
	case tea.MouseMsg:
		if m.edit == editNone || true {
			return m.mouse(msg)
		}
	case tea.KeyMsg:
		if m.edit != editNone {
			switch msg.String() {
			case "esc":
				return m.activate("cancel")
			case "enter":
				return m.activate("save")
			}
			var cmd tea.Cmd
			m.input, cmd = m.input.Update(msg)
			return m, cmd
		}
		switch msg.String() {
		case "ctrl+c", "q":
			return m, tea.Quit
		case "tab", "right", "l":
			return m.activate(fmt.Sprintf("tab:%d", (m.tab+1)%len(tabNames)))
		case "shift+tab", "left", "h":
			return m.activate(fmt.Sprintf("tab:%d", (m.tab+len(tabNames)-1)%len(tabNames)))
		case "up", "k":
			m.moveCursor(-1)
		case "down", "j":
			m.moveCursor(1)
		case " ":
			if m.tab == tabMods {
				return m.activate(fmt.Sprintf("mod:%d", m.mi))
			}
		case "enter":
			switch m.tab {
			case tabPlay:
				return m.activate("launchworld")
			case tabSync:
				return m.activate("sync")
			case tabMods:
				return m.activate(fmt.Sprintf("mod:%d", m.mi))
			}
		case "[":
			return m.activate("prevw")
		case "]":
			return m.activate("nextw")
		}
	}
	return m, nil
}

func (m *model) moveCursor(d int) {
	switch m.tab {
	case tabPlay:
		if n := len(m.worlds); n > 0 {
			m.wi = (m.wi + d + n) % n
		}
	case tabMods:
		if m.mi+d >= 0 && m.mi+d < len(m.mods) {
			m.mi += d
		}
		m.clampScroll()
	}
}

func (m model) rowsVisible() int {
	r := m.h - 14
	if r < 3 {
		r = 3
	}
	return r
}

func (m *model) clampScroll() {
	vis := m.rowsVisible()
	if m.mi < m.moff {
		m.moff = m.mi
	}
	if m.mi >= m.moff+vis {
		m.moff = m.mi - vis + 1
	}
	if max := len(m.mods) - vis; m.moff > max {
		m.moff = max
	}
	if m.moff < 0 {
		m.moff = 0
	}
}

func (m model) mouse(msg tea.MouseMsg) (tea.Model, tea.Cmd) {
	switch {
	case msg.Button == tea.MouseButtonWheelUp || msg.Button == tea.MouseButtonWheelDown:
		if m.tab == tabMods && m.edit == editNone {
			d := 1
			if msg.Button == tea.MouseButtonWheelUp {
				d = -1
			}
			m.moff += d * 2
			if max := len(m.mods) - m.rowsVisible(); m.moff > max {
				m.moff = max
			}
			if m.moff < 0 {
				m.moff = 0
			}
		}
	case msg.Action == tea.MouseActionMotion:
		m.hover = ""
		for _, id := range *m.reg {
			if zone.Get(id).InBounds(msg) {
				m.hover = id
				break
			}
		}
	case msg.Action == tea.MouseActionRelease && msg.Button == tea.MouseButtonLeft:
		for _, id := range *m.reg {
			if zone.Get(id).InBounds(msg) {
				return m.activate(id)
			}
		}
	}
	return m, nil
}

// ---- drawing --------------------------------------------------------------------------------

func (m model) mark(id, s string) string {
	*m.reg = append(*m.reg, id)
	return zone.Mark(id, s)
}

// button draws a bordered button; primary = filled. Hover/disabled change the colours.
func (m model) button(id, label string, primary, disabled bool) string {
	st := lipgloss.NewStyle().Padding(0, 2).Border(lipgloss.RoundedBorder())
	hot := m.hover == id
	switch {
	case disabled:
		st = st.Foreground(cLine).BorderForeground(cLine)
	case primary && hot:
		st = st.Foreground(lipgloss.Color("231")).Background(cAccent).BorderForeground(cAccent).Bold(true)
	case primary:
		st = st.Foreground(lipgloss.Color("231")).Background(cPrim).BorderForeground(cPrim).Bold(true)
	case hot:
		st = st.Foreground(cAccent).BorderForeground(cAccent)
	default:
		st = st.Foreground(cText).BorderForeground(cLine)
	}
	out := st.Render(label)
	if disabled {
		return out
	}
	return m.mark(id, out)
}

func (m model) row(id, text string, selected bool, width int) string {
	st := lipgloss.NewStyle().Width(width).Padding(0, 1)
	switch {
	case selected:
		st = st.Foreground(lipgloss.Color("231")).Background(cPrim).Bold(true)
	case m.hover == id:
		st = st.Foreground(cAccent).Background(lipgloss.Color("236"))
	default:
		st = st.Foreground(cText)
	}
	return m.mark(id, st.Render(text))
}

func (m model) panel(title, body string, width int) string {
	st := lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(cLine).Padding(0, 1).Width(width)
	head := lipgloss.NewStyle().Bold(true).Foreground(cAccent).Render(title)
	if title != "" {
		body = head + "\n" + body
	}
	return st.Render(body)
}

func (m model) selector(width int) string {
	name := "(no worlds)"
	if w, ok := m.world(); ok {
		name = w.Name
	}
	mid := lipgloss.NewStyle().Width(width - 24).Align(lipgloss.Center).Bold(true).Foreground(cAccent).Render("World: " + name)
	return lipgloss.JoinHorizontal(lipgloss.Center, m.button("prevw", "◀", false, len(m.worlds) < 2), mid, m.button("nextw", "▶", false, len(m.worlds) < 2))
}

func (m model) View() string {
	*m.reg = (*m.reg)[:0]
	cw := m.w - 4
	if cw > 100 {
		cw = 100
	}
	if cw < 50 {
		cw = 50
	}
	dim := lipgloss.NewStyle().Foreground(cDim)

	// header
	install := "no Luanti install found"
	if m.found {
		install = m.in.Kind + " - " + m.in.DataDir
	}
	head := lipgloss.NewStyle().Bold(true).Foreground(cAccent).Render("Luanti Launcher") + "  " + dim.Render(install)

	// tabs
	var tabs []string
	for i, n := range tabNames {
		id := fmt.Sprintf("tab:%d", i)
		st := lipgloss.NewStyle().Padding(0, 2)
		switch {
		case i == m.tab:
			st = st.Bold(true).Foreground(lipgloss.Color("231")).Background(cPrim)
		case m.hover == id:
			st = st.Foreground(cAccent)
		default:
			st = st.Foreground(cText)
		}
		tabs = append(tabs, m.mark(id, st.Render(n)))
	}
	qst := lipgloss.NewStyle().Padding(0, 2).Foreground(cDim)
	if m.hover == "quit" {
		qst = qst.Foreground(cErr)
	}
	tabs = append(tabs, qst.Render(" "), m.mark("quit", qst.Render("Quit")))
	tabbar := lipgloss.JoinHorizontal(lipgloss.Bottom, tabs...) + "\n" + lipgloss.NewStyle().Foreground(cLine).Render(strings.Repeat("─", cw))

	var body string
	switch {
	case m.edit != editNone:
		body = m.viewEdit(cw)
	case m.tab == tabPlay:
		body = m.viewPlay(cw)
	case m.tab == tabMods:
		body = m.viewMods(cw)
	case m.tab == tabFolders:
		body = m.viewFolders(cw)
	case m.tab == tabSync:
		body = m.viewSync(cw)
	default:
		body = m.viewSettings(cw)
	}

	status := ""
	if m.status != "" {
		c := cOk
		if m.isErr {
			c = cErr
		}
		status = lipgloss.NewStyle().Foreground(c).Width(cw).Render(m.status)
	}
	help := dim.Render("mouse: click tabs, buttons and rows  |  keys: tab / arrows, enter, space, [ ] world, q quit")
	out := lipgloss.NewStyle().PaddingLeft(1).Render(lipgloss.JoinVertical(lipgloss.Left, "", head, "", tabbar, body, "", status, help))
	return zone.Scan(out)
}

func (m model) viewPlay(cw int) string {
	var rows []string
	for i, w := range m.worlds {
		rows = append(rows, m.row(fmt.Sprintf("world:%d", i), w.Name, i == m.wi, cw-6))
	}
	if len(rows) == 0 {
		rows = []string{lipgloss.NewStyle().Foreground(cDim).Render("(no worlds in " + m.in.DataDir + "/worlds)")}
	}
	list := m.panel("Worlds", strings.Join(rows, "\n"), cw-2)
	btns := lipgloss.JoinHorizontal(lipgloss.Top,
		m.button("launchworld", "Launch selected world", true, len(m.worlds) == 0 || !m.found), " ",
		m.button("launch", "Open Luanti menu", false, !m.found))
	return lipgloss.JoinVertical(lipgloss.Left, list, btns)
}

func (m model) viewMods(cw int) string {
	if len(m.worlds) == 0 {
		return m.panel("Mods", "No worlds found.", cw-2)
	}
	var rows []string
	vis := m.rowsVisible()
	for i := m.moff; i < len(m.mods) && i < m.moff+vis; i++ {
		mark := "[ ]"
		if m.mt != nil && m.mt.modEnabled(m.mods[i]) {
			mark = "[x]"
		}
		rows = append(rows, m.row(fmt.Sprintf("mod:%d", i), mark+"  "+m.mods[i], i == m.mi, cw-6))
	}
	if len(m.mods) == 0 {
		rows = []string{"(no mods in " + m.in.DataDir + "/mods - run Sync)"}
	}
	foot := lipgloss.NewStyle().Foreground(cDim).Render(fmt.Sprintf("%d mods - click a row or press space to switch it on or off in this world", len(m.mods)))
	list := m.panel("Mods in this world", strings.Join(rows, "\n")+"\n"+foot, cw-2)
	btns := lipgloss.JoinHorizontal(lipgloss.Top, m.button("allon", "Enable all", false, false), " ", m.button("alloff", "Disable all", false, false))
	return lipgloss.JoinVertical(lipgloss.Left, m.selector(cw-2), list, btns)
}

func (m model) viewFolders(cw int) string {
	w, ok := m.world()
	if !ok {
		return m.panel("Folders", "No worlds found.", cw-2)
	}
	var cards []string
	for i, f := range managedFolders {
		files := listFolder(w, f)
		info := fmt.Sprintf("%d files  -  %s/%s", len(files), w.Name, f.Rel)
		left := lipgloss.NewStyle().Width(cw - 24).Render(lipgloss.NewStyle().Bold(true).Render(f.Label) + "\n" + lipgloss.NewStyle().Foreground(cDim).Render(info))
		cards = append(cards, m.panel("", lipgloss.JoinHorizontal(lipgloss.Center, left, m.button(fmt.Sprintf("folder:%d", i), "Add files...", false, false)), cw-2))
	}
	return lipgloss.JoinVertical(lipgloss.Left, append([]string{m.selector(cw - 2)}, cards...)...)
}

func (m model) viewSync(cw int) string {
	src := m.cfg.ModsSource
	if src == "" {
		src = "(not set - Settings)"
	}
	txt := "Copies every mod from\n  " + src + "\ninto\n  " + m.in.DataDir + "/mods\nOnly mods this launcher installed are ever removed."
	return lipgloss.JoinVertical(lipgloss.Left, m.panel("Sync mods", txt, cw-2), m.button("sync", "Sync now", true, !m.found || m.cfg.ModsSource == ""))
}

func (m model) viewSettings(cw int) string {
	labels := []string{"Mods source folder", "Luanti data folder", "Launch command", "Game source folder"}
	vals := []string{m.cfg.ModsSource, m.cfg.DataDir, m.cfg.Command, m.cfg.GameSource}
	autos := []string{"", m.in.DataDir, strings.Join(m.in.Cmd, " "), ""}
	var rows []string
	for i := range labels {
		v := vals[i]
		if v == "" {
			v = lipgloss.NewStyle().Foreground(cDim).Render("(auto) " + autos[i])
		}
		left := lipgloss.NewStyle().Width(cw - 18).Render(lipgloss.NewStyle().Bold(true).Render(labels[i]) + "\n" + v)
		rows = append(rows, lipgloss.JoinHorizontal(lipgloss.Center, left, m.button(fmt.Sprintf("set:%d", i), "Edit", false, false)))
	}
	cfg := lipgloss.NewStyle().Foreground(cDim).Render("Saved in " + m.cfgPath + " (next to the launcher; nothing is written elsewhere)")
	return m.panel("Settings", strings.Join(rows, "\n")+"\n"+cfg, cw-2)
}

func (m model) viewEdit(cw int) string {
	title := "Edit setting"
	if m.edit == editFolder {
		w, _ := m.world()
		title = "Add to " + managedFolders[m.editIdx].Label + " - world " + w.Name
	} else {
		title = "Edit: " + []string{"Mods source folder", "Luanti data folder", "Launch command", "Game source folder"}[m.editIdx]
	}
	btns := lipgloss.JoinHorizontal(lipgloss.Top, m.button("save", "Save", true, false), " ", m.button("cancel", "Cancel", false, false))
	return lipgloss.JoinVertical(lipgloss.Left, m.panel(title, m.input.View(), cw-2), btns)
}
