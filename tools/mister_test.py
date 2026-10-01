#!/usr/bin/env python3
"""Hardware test suite for the SharpMZ core on a MiSTer.

Each test is an MGL that loads the core with its own <setname>, so it gets its own config file
(<setname>_v5.CFG) holding the OSD settings (model etc.). The MGL mounts the tape/disk images
and resets; this script then types keys through mrext's remote API (keyboard-raw) and takes
screenshots with Main's `screenshot` command, then copies them back.

Needs: root ssh to the MiSTer, mrext remote running (port 8182). The software comes from the
repository's gitignored folders (software/, verilator test programs) and is copied to
games/SharpMZ/HWTest on the MiSTer; disk images are copied fresh for each run because the core
writes back to them.

usage: mister_test.py [--host mister.local] [--rbf output_files/sharpmz.rbf] [--only T03,T08]
                      [--out out/mister] [--no-deploy]
"""
import argparse, datetime, os, socket, subprocess, sys, time, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SW = os.path.join(ROOT, 'software')
GAMES800 = os.path.join(SW, 'MZ-800-full/MZ-800/MZ-800 Software/COM/MZF/Games/800')
DSK = os.path.join(SW, 'dsk')
RB = os.path.join(SW, 'idealine/mz-80b/rb_DSK/DSK')
TESTS = os.path.join(ROOT, 'verilator/tests/mz800')
MZF = os.path.join(ROOT, 'rtl/software/mzf')
FAT = '/media/fat'
HW = f'{FAT}/games/SharpMZ/HWTest'
CFG_VER = '_v5'           # CONF_STR "v,5"

# Model menu entries (status[3:1]), in CONF_STR order.
MODEL = {'MZ80A': 0, 'MZ80K': 1, 'MZ80C': 2, 'MZ1200': 3, 'MZ700': 4, 'MZ80B': 5, 'MZ2000': 6, 'MZ800': 7}


def status_bytes(model, opts=()):
    """16-byte CFG: status bit n is byte n/8, bit n%8. opts: (low_bit, width, value)."""
    st = MODEL[model] << 1
    for lo, width, val in opts:
        st |= (val & ((1 << width) - 1)) << lo
    return st.to_bytes(16, 'little')


FAST_TAPE = lambda step: (21, 3, step)     # OSD Fast Tape: 0 Default, 1 Off, 2 2x .. 6 32x
MZ800_MODE = (32, 1, 1)                    # rear switch in the MZ-800 position

# A test: name, model, OSD options, files to mount [(kind, index, local source)], reset after
# mounting, then steps: ('wait', s) / ('type', text) / ('shot', label).
# kind: 's' = image slot (S0 tape, S1/S2 floppy), 'f' = file load (F1 tape to CMT, F2 direct).
T = []
def test(name, model, desc, files=(), opts=(), reset=False, steps=()):
    T.append(dict(name=name, model=model, desc=desc, files=list(files), opts=list(opts), reset=reset, steps=list(steps)))

test('T01', 'MZ80K', 'MZ-80K boots to the SP-1002 monitor', steps=[('wait', 4), ('shot', 'boot')])
test('T02', 'MZ80A', 'MZ-80A boots to the SA-1510 monitor', steps=[('wait', 4), ('shot', 'boot')])
test('T03', 'MZ700', 'MZ-700 boots to the 1Z-013A monitor', steps=[('wait', 4), ('shot', 'boot')])
test('T04', 'MZ800', 'MZ-800 IPL menu', steps=[('wait', 4), ('shot', 'boot')])
test('T05', 'MZ80B', 'MZ-80B IPL (no disk: asks for the tape)', steps=[('wait', 6), ('shot', 'boot')])
test('T06', 'MZ2000', 'MZ-2000 IPL: "IPL is looking for a program"', steps=[('wait', 6), ('shot', 'boot')])
test('T07', 'MZ700', 'MZ-700 tape: L loads ramtest from the CMT', files=[('f', 1, f'{MZF}/ramtest.mzf')],
     steps=[('wait', 2), ('type', 'L\n'), ('wait', 20), ('shot', 'loaded')])
test('T08', 'MZ700', 'MZ-700 floppy: J F000 boots a disk (MZ-1E05 ROM)', files=[('s', 1, 'gen:fd700')], reset=True,
     steps=[('wait', 3), ('type', 'JF000\n'), ('wait', 12), ('shot', 'booted')])
test('T09', 'MZ800', 'MZ-800 graphics 640x200 test program (direct load, M, J2000)', files=[('f', 2, f'{TESTS}/gfx640.mzf')],
     steps=[('wait', 2), ('type', 'M'), ('wait', 2), ('type', 'J2000\n'), ('wait', 6), ('shot', 'gfx640')])
test('T10', 'MZ800', 'MZ-800 graphics 320x200 16 colours (direct load, M, J2000)', files=[('f', 2, f'{TESTS}/gfx320h.mzf')],
     steps=[('wait', 2), ('type', 'M'), ('wait', 2), ('type', 'J2000\n'), ('wait', 6), ('shot', 'gfx320h')])
test('T11', 'MZ800', 'MZ-800 IPL loads Cauldron II from a tape image (C)', files=[('s', 0, f'{GAMES800}/Cauldron.mzf')],
     opts=[FAST_TAPE(5)], steps=[('wait', 10), ('type', 'C'), ('wait', 45), ('shot', '45s'), ('wait', 30), ('shot', '75s')])
test('T12', 'MZ800', 'MZ-800 IPL loads Cybernoid from a tape image (C)', files=[('s', 0, f'{GAMES800}/Cyberno.mzf')],
     opts=[FAST_TAPE(5)], steps=[('wait', 10), ('type', 'C'), ('wait', 45), ('shot', '45s'), ('wait', 30), ('shot', '75s')])
test('T13', 'MZ800', 'MZ-800 CP/M 4.1 boots from floppy; DIR', files=[('s', 1, f'{DSK}/CPMv41 System.dsk')], reset=True,
     steps=[('wait', 15), ('shot', 'boot'), ('type', 'DIR\n'), ('wait', 4), ('shot', 'dir')])
test('T14', 'MZ800', 'MZ-800 CP/M 1.3 boots from floppy', files=[('s', 1, f'{DSK}/CPMv13A System.dsk')], reset=True,
     steps=[('wait', 20), ('shot', 'boot')])
test('T15', 'MZ800', 'MZ-800 CPMv41 Hry COM A: file manager autostarts', files=[('s', 1, f'{DSK}/CPMv41 Hry COM A.dsk')], reset=True,
     steps=[('wait', 20), ('shot', 'boot')])
test('T16', 'MZ80B', 'MZ-80B floppy: SB-6511 Disk BASIC (DISK23)', files=[('s', 1, f'{RB}/DISK23.DSK')], reset=True,
     steps=[('wait', 20), ('shot', 'boot')])
test('T17', 'MZ80B', 'MZ-80B floppy: CP/M 2.2 (DISK01)', files=[('s', 1, f'{RB}/DISK01.DSK')], reset=True,
     steps=[('wait', 25), ('shot', 'boot')])
test('T18', 'MZ2000', 'MZ-2000 floppy: MZ-80B CP/M 2.2 (black screen in the sim)', files=[('s', 1, f'{RB}/DISK01.DSK')], reset=True,
     steps=[('wait', 25), ('shot', 'boot')])
test('T19', 'MZ700', 'MZ-700 sound: BELL (880 Hz) then a steady 440 Hz A (listen)', files=[('f', 2, f'{ROOT}/verilator/tests/sound/beep700.mzf')],
     steps=[('wait', 2), ('type', 'J2000\n'), ('wait', 3), ('shot', 'beep')])
test('T20', 'MZ800', 'MZ-800 sound: the same BELL and 440 Hz A through the 8253 (listen)', files=[('f', 2, f'{ROOT}/verilator/tests/sound/beep700.mzf')],
     steps=[('wait', 2), ('type', 'M'), ('wait', 2), ('type', 'J2000\n'), ('wait', 3), ('shot', 'beep')])
test('T21', 'MZ80B', 'MZ-80B tape: the IPL loads SB-5520 BASIC from a tape image', files=[('s', 0, f'{SW}/mz80b/SB-5520.mzt')],
     opts=[FAST_TAPE(5)], reset=True, steps=[('wait', 40), ('shot', 'basic')])
test('T22', 'MZ2000', 'MZ-2000 tape: the IPL loads Gang Man (Hudson Soft)', files=[('s', 0, f'{SW}/mz2200/Gang Man (1983)(Hudson Soft)(Fumihiko Itagaki) [CT].mzt')],
     opts=[FAST_TAPE(5)], reset=True, steps=[('wait', 40), ('shot', 'title')])
test('T23', 'MZ2000', 'MZ-2000 floppy: TF-DOS boot disk (fukui brave.d88)', files=[('s', 1, f'{SW}/fukui-mz2000/brave.d88')], reset=True,
     steps=[('wait', 25), ('shot', 'boot')])
test('T24', 'MZ2000', 'MZ-2000 tape: Zero Fighter (Hudson Soft), colour title screen', files=[('s', 0, f'{SW}/mz2200/Zero Fighter (1983)(Hudosn Soft) [CT].mzt')],
     opts=[FAST_TAPE(5)], reset=True, steps=[('wait', 40), ('shot', 'title')])

# Linux input key codes (uinput); a leading '-' holds shift (mrext keyboard-raw).
KEYS = {'\n': 28, ' ': 57, '-': 12, '=': 13, ';': 39, "'": 40, ',': 51, '.': 52, '/': 53, ':': -39, '*': -9}
KEYS.update({c: k for c, k in zip('1234567890', range(2, 12))})
KEYS.update({c: k for c, k in zip('QWERTYUIOP', range(16, 26))})
KEYS.update({c: k for c, k in zip('ASDFGHJKL', range(30, 39))})
KEYS.update({c: k for c, k in zip('ZXCVBNM', range(44, 51))})


def sh(cmd, **kw):
    return subprocess.run(cmd, shell=True, check=True, **kw)


class Mister:
    def __init__(self, host):
        self.host = host
        self.ip = socket.getaddrinfo(host, None, socket.AF_INET)[0][4][0]

    def ssh(self, cmd, capture=False):
        r = subprocess.run(['ssh', f'root@{self.host}', cmd], check=True, capture_output=capture, text=True)
        return r.stdout if capture else None

    def put(self, local, remote):
        sh(f'scp -q "{local}" "root@{self.host}:{remote}"')

    def cmd(self, c):
        self.ssh(f'echo "{c}" > /dev/MiSTer_cmd')

    def key(self, code):
        req = urllib.request.Request(f'http://{self.ip}:8182/api/controls/keyboard-raw/{code}', method='POST')
        urllib.request.urlopen(req, timeout=5).read()

    def type(self, text):
        for c in text.upper():
            self.key(KEYS[c])
            time.sleep(0.15)


def mgl(rbf, t, remote_files):
    x = ['<mistergamedescription>', f'  <rbf>{rbf}</rbf>', f'  <setname same_dir="1">{t["name"]}</setname>']
    for (kind, index, _), path in zip(t['files'], remote_files):
        x.append(f'  <file delay="2" type="{kind}" index="{index}" path="{path}"/>')
    if t['reset']:
        x.append('  <reset delay="1"/>')
    x.append('</mistergamedescription>')
    return '\n'.join(x) + '\n'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', default='mister.local')
    ap.add_argument('--rbf', default=os.path.join(ROOT, 'output_files/sharpmz.rbf'))
    ap.add_argument('--only')
    ap.add_argument('--out', default=os.path.join(ROOT, 'out/mister'))
    ap.add_argument('--no-deploy', action='store_true', help='use the RBF already on the MiSTer')
    a = ap.parse_args()
    tests = [t for t in T if not a.only or t['name'] in a.only.split(',')]
    m = Mister(a.host)
    stage = os.path.join(a.out, 'stage')
    os.makedirs(stage, exist_ok=True)

    rbf_name = 'SharpMZ-std_' + datetime.date.today().strftime('%Y%m%d')
    if not a.no_deploy:
        m.ssh(f'mkdir -p {HW}/mgl {HW}/disks')
        m.put(a.rbf, f'{FAT}/_Computer/{rbf_name}.rbf')
    else:
        rbf_name = m.ssh(f'cd {FAT}/_Computer && ls SharpMZ-std_*.rbf | sort | tail -1', True).strip()[:-4]

    for t in tests:
        remote = []
        for kind, index, src in t['files']:
            if src == 'gen:fd700':        # MZ-700 boot disk made from ramtest
                src = os.path.join(stage, 'fd700_ramtest.dsk')
                sh(f'python3 "{ROOT}/tools/make_boot_disk.py" "{MZF}/ramtest.mzf" "{src}" > /dev/null')
            if not os.path.exists(src):
                sys.exit(f'{t["name"]}: missing {src}')
            ext = os.path.splitext(src)[1].lower()
            dst = f'{HW}/{"disks" if kind == "s" and index > 0 else "files"}/{t["name"]}_{index}{ext}'
            m.ssh(f'mkdir -p "{os.path.dirname(dst)}"')
            m.put(src, dst)
            remote.append(dst)
        cfg = os.path.join(stage, f'{t["name"]}{CFG_VER}.CFG')
        open(cfg, 'wb').write(status_bytes(t['model'], t['opts']))
        m.put(cfg, f'{FAT}/config/{t["name"]}{CFG_VER}.CFG')
        path = os.path.join(stage, f'{t["name"]}.mgl')
        open(path, 'w').write(mgl(f'_Computer/{rbf_name}', t, remote))
        m.put(path, f'{HW}/mgl/{t["name"]}.mgl')

    results = []
    for t in tests:
        print(f'{t["name"]} {t["model"]}: {t["desc"]}', flush=True)
        m.ssh(f'rm -f {FAT}/screenshots/{t["name"]}_*.png')
        m.cmd(f'load_core {HW}/mgl/{t["name"]}.mgl')
        time.sleep(4 + 2 * len(t['files']) + (2 if t['reset'] else 0))
        shots = []
        for op, arg in t['steps']:
            if op == 'wait':
                time.sleep(arg)
            elif op == 'type':
                m.type(arg)
            elif op == 'shot':
                m.cmd(f'screenshot {t["name"]}_{arg}.png')
                time.sleep(1.5)
                shots.append(f'{t["name"]}_{arg}.png')
        d = os.path.join(a.out, 'shots')
        os.makedirs(d, exist_ok=True)
        for s in shots:
            r = subprocess.run(f'scp -q "root@{a.host}:{FAT}/screenshots/{s}" "{d}/{s}"', shell=True)
            results.append((t['name'], t['desc'], s, r.returncode == 0))
            print(f'   {s}: {"ok" if r.returncode == 0 else "MISSING"}', flush=True)

    with open(os.path.join(a.out, 'index.html'), 'w') as f:
        f.write('<!doctype html><meta charset="utf-8"><title>SharpMZ hardware tests</title>'
                '<style>body{font:14px sans-serif;background:#222;color:#ddd}img{width:480px;image-rendering:pixelated}'
                'div{display:inline-block;margin:8px;vertical-align:top;width:480px}</style>\n')
        for name, desc, s, ok in results:
            f.write(f'<div><b>{s}</b><br>{desc}<br>' + (f'<img src="shots/{s}">' if ok else 'missing') + '</div>\n')
    print(f'{a.out}/index.html')


if __name__ == '__main__':
    main()
