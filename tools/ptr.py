"""Virtual absolute mouse through /dev/uinput (dev tool, host only; needs write access to /dev/uinput).
   ptr.py move X Y | click X Y | hold X Y SECS | where      (X,Y = screen pixels, screen is read from kscreen or SCREEN=WxH)
Each call creates a fresh device, waits for the compositor to notice it, acts, then removes it."""
import os, sys, fcntl, struct, time, subprocess, re
UI_SET_EVBIT, UI_SET_KEYBIT, UI_SET_ABSBIT = 0x40045564, 0x40045565, 0x40045567
UI_DEV_CREATE, UI_DEV_DESTROY = 0x5501, 0x5502
EV_SYN, EV_KEY, EV_ABS, BTN_LEFT, ABS_X, ABS_Y = 0, 1, 3, 0x110, 0, 1

def screen():
    s = os.environ.get('SCREEN')
    if s: return tuple(int(v) for v in s.split('x'))
    return (1920, 1080)

def dev(w, h):
    fd = os.open('/dev/uinput', os.O_WRONLY | os.O_NONBLOCK)
    for ev in (EV_KEY, EV_ABS, EV_SYN): fcntl.ioctl(fd, UI_SET_EVBIT, ev)
    fcntl.ioctl(fd, UI_SET_KEYBIT, BTN_LEFT)
    fcntl.ioctl(fd, UI_SET_ABSBIT, ABS_X); fcntl.ioctl(fd, UI_SET_ABSBIT, ABS_Y)
    absmax = [0] * 64; absmax[ABS_X] = w - 1; absmax[ABS_Y] = h - 1
    setup = struct.pack('80sHHHHI', b'lt-ptr', 3, 0x1209, 0x7777, 1, 0) + struct.pack('64i', *absmax) + struct.pack('64i', *([0] * 64)) * 3
    os.write(fd, setup); fcntl.ioctl(fd, UI_DEV_CREATE)
    time.sleep(1.5)
    return fd

def emit(fd, t, c, v): os.write(fd, struct.pack('qqHHi', 0, 0, t, c, v))
def sync(fd): emit(fd, EV_SYN, 0, 0)
def move(fd, x, y):
    emit(fd, EV_ABS, ABS_X, int(x)); emit(fd, EV_ABS, ABS_Y, int(y)); sync(fd); time.sleep(0.15)

def where():
    js = '/tmp/lt_where.js'
    open(js, 'w').write('print("LTWHERE " + workspace.cursorPos.x + " " + workspace.cursorPos.y);')
    subprocess.run(['qdbus6', 'org.kde.KWin', '/Scripting', 'org.kde.kwin.Scripting.loadScript', js, 'lt_where'], capture_output=True)
    subprocess.run(['qdbus6', 'org.kde.KWin', '/Scripting', 'org.kde.kwin.Scripting.start'], capture_output=True); time.sleep(0.6)
    out = subprocess.run(['journalctl', '--user', '--since', '20 sec ago'], capture_output=True, text=True).stdout
    subprocess.run(['qdbus6', 'org.kde.KWin', '/Scripting', 'org.kde.kwin.Scripting.unloadScript', 'lt_where'], capture_output=True)
    m = re.findall(r'LTWHERE (\S+) (\S+)', out)
    print('cursor', m[-1][0], m[-1][1] if m else 'unknown')

a = sys.argv[1:]
if not a: sys.exit(__doc__)
if a[0] == 'where': where(); sys.exit(0)
w, h = screen(); fd = dev(w, h)
try:
    if a[0] == 'move': move(fd, a[1], a[2])
    elif a[0] == 'click':
        move(fd, a[1], a[2]); emit(fd, EV_KEY, BTN_LEFT, 1); sync(fd); time.sleep(0.12); emit(fd, EV_KEY, BTN_LEFT, 0); sync(fd)
    elif a[0] == 'hold':   # hold X Y SECS: press at X,Y, keep it down SECS seconds (run it in the background, snap meanwhile), release
        move(fd, a[1], a[2]); emit(fd, EV_KEY, BTN_LEFT, 1); sync(fd); time.sleep(float(a[3])); emit(fd, EV_KEY, BTN_LEFT, 0); sync(fd)
    elif a[0] == 'down': emit(fd, EV_KEY, BTN_LEFT, 1); sync(fd)
    elif a[0] == 'up': emit(fd, EV_KEY, BTN_LEFT, 0); sync(fd)
    time.sleep(0.3)
finally:
    fcntl.ioctl(fd, UI_DEV_DESTROY); os.close(fd)
