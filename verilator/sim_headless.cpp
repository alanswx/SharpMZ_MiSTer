// Headless SharpMZ simulation: boot, type, load tapes, capture frames.
//
// The command line follows refs/mz800emu's headless CLI (HEADLESS_CLI.md) so a
// run on the core and on the reference emulator can be compared directly:
//
//   ./obj_dir_headless/Vtop --model mz700 --stop-at-frame 150 --ascii-end
//   ./obj_dir_headless/Vtop --mzf ../rtl/software/mzf/ramtest.mzf --type '100:L\n' \
//       --stop-at-frame 900 --screenshot 900 --frame-log out/frames.csv
//
// Run from this directory: the RAM init files are ./software/mif/*.hex.

#include "Vtop.h"
#include "verilated.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include "ps2_keys.h"
#include "sharp_vcode.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fstream>
#include <map>
#include <memory>
#include <set>
#include <string>
#include <sys/stat.h>
#include <vector>

static const double CLK_HZ = 70937600.0;

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------
struct MemDump { uint32_t addr, len; std::string path; };
struct TypeCmd { uint32_t frame; std::string text; };

struct Options {
    std::string model = "mz700";
    std::string vmode = "native";
    int      turbo = 0;
    int      fast_tape = 1;           // Menu step 1 = off (real speed), as the reference emulator runs.
    uint32_t stop_frame = 0;
    bool     stop_set = false;
    std::string mzf;
    bool     mzf_direct = false;
    uint32_t mzf_direct_frame = 0;
    std::vector<TypeCmd> types;
    uint32_t type_press = 3, type_release = 3;
    std::set<uint32_t> screenshots;
    bool     dump_range = false;
    uint32_t dump_from = 0, dump_to = 0, dump_every = 0;
    std::string out_dir = "out";
    std::string frame_log;
    bool     ascii_end = false;
    int      ascii_cols = 40;
    std::vector<MemDump> memdumps;
    std::string trace_file;
    uint32_t trace_from = 0, trace_to = UINT32_MAX;
    bool     quiet = false;
};

static void usage()
{
    fprintf(stderr,
"SharpMZ core simulation (headless)\n"
"\n"
"Machine and run:\n"
"  --model M              mz80k|mz80c|mz1200|mz80a|mz700|mz800|mz80b|mz2000 (default mz700)\n"
"  --vmode native|vga60   video timing (default native)\n"
"  --turbo N              CPU speed menu step 0..7 (default 0 = machine speed)\n"
"  --fast-tape N          tape speed menu step 0..7 (default 1 = off, real speed)\n"
"  --stop-at-frame N      exit after frame N (frames count vsyncs from reset)\n"
"  --quiet                no progress on stderr\n"
"Tapes:\n"
"  --mzf FILE             put an MZF in the tape buffer (Load Tape to CMT)\n"
"  --mzf-direct           load it straight to RAM instead (Load Direct to RAM)\n"
"  --mzf-direct-frame N   frame to do the direct load at (default 0)\n"
"Typing:\n"
"  --type FRAME:TEXT      type TEXT from FRAME; \\n or {RETURN}, {BREAK}, {DEL}, {INS},\n"
"                         {HOME}, {CLR}, {UP}, {DOWN}, {LEFT}, {RIGHT}, {WAIT n}\n"
"  --type-rate P:R        frames per key press:release (default 3:3)\n"
"Images and logs:\n"
"  --screenshot N         PNG of frame N (repeatable)\n"
"  --dump-frames A:B      PNG of every frame A..B\n"
"  --dump-every K         PNG of every Kth frame\n"
"  --out DIR              output directory (default ./out)\n"
"  --frame-log FILE       frame,fb_hash,cpu_cycles,pc per frame\n"
"  --ascii-end            print the text screen (display codes -> ASCII) at exit\n"
"  --ascii-cols 40|80     text width for --ascii-end (default 40)\n"
"  --dump-mem A:L:FILE    write main RAM A..A+L-1 at exit (physical RAM, not the\n"
"                         CPU's banked view; addresses in hex or decimal)\n"
"  --trace-cpu FILE       PC of each instruction fetch\n"
"  --trace-from N         start tracing at frame N; --trace-to N stops after frame N\n"
"\n"
"fb_hash is FNV-1a 32 over the RGB888 bytes of the active (unblanked) picture,\n"
"the same bytes written to the PNG. cpu_cycles counts CPU clock enables (T-states).\n"
"Exit codes: 0 ok, 2 bad arguments or files, 3 runtime failure.\n");
}

static uint32_t parse_num(const std::string &s)
{
    return (uint32_t)strtoul(s.c_str(), nullptr, 0);
}

static bool parse_args(int argc, char **argv, Options &o)
{
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        auto next = [&](void) -> std::string {
            if (i + 1 >= argc) { fprintf(stderr, "%s needs a value\n", a.c_str()); exit(2); }
            return argv[++i];
        };
        if (a == "--help" || a == "-h") { usage(); exit(0); }
        else if (a == "--headless") {}
        else if (a == "--model") o.model = next();
        else if (a == "--vmode") o.vmode = next();
        else if (a == "--turbo") o.turbo = (int)parse_num(next());
        else if (a == "--fast-tape") o.fast_tape = (int)parse_num(next());
        else if (a == "--stop-at-frame") { o.stop_frame = parse_num(next()); o.stop_set = true; }
        else if (a == "--quiet") o.quiet = true;
        else if (a == "--mzf") o.mzf = next();
        else if (a == "--mzf-direct") o.mzf_direct = true;
        else if (a == "--mzf-direct-frame") o.mzf_direct_frame = parse_num(next());
        else if (a == "--run-mzf") { o.mzf = next(); o.mzf_direct = true; }
        else if (a == "--type") {
            std::string v = next();
            size_t c = v.find(':');
            if (c == std::string::npos) { fprintf(stderr, "--type wants FRAME:TEXT\n"); return false; }
            o.types.push_back({parse_num(v.substr(0, c)), v.substr(c + 1)});
        }
        else if (a == "--type-rate") {
            std::string v = next();
            size_t c = v.find(':');
            o.type_press = parse_num(v.substr(0, c));
            o.type_release = c == std::string::npos ? o.type_press : parse_num(v.substr(c + 1));
        }
        else if (a == "--screenshot") o.screenshots.insert(parse_num(next()));
        else if (a == "--dump-frames") {
            std::string v = next();
            size_t c = v.find(':');
            o.dump_range = true;
            o.dump_from = parse_num(v.substr(0, c));
            o.dump_to = c == std::string::npos ? o.dump_from : parse_num(v.substr(c + 1));
        }
        else if (a == "--dump-every") o.dump_every = parse_num(next());
        else if (a == "--out") o.out_dir = next();
        else if (a == "--frame-log") o.frame_log = next();
        else if (a == "--ascii-end") o.ascii_end = true;
        else if (a == "--ascii-cols") o.ascii_cols = (int)parse_num(next());
        else if (a == "--dump-mem") {
            std::string v = next();
            size_t c1 = v.find(':'), c2 = v.find(':', c1 + 1);
            if (c1 == std::string::npos || c2 == std::string::npos) { fprintf(stderr, "--dump-mem wants ADDR:LEN:FILE\n"); return false; }
            o.memdumps.push_back({parse_num(v.substr(0, c1)), parse_num(v.substr(c1 + 1, c2 - c1 - 1)), v.substr(c2 + 1)});
        }
        else if (a == "--trace-cpu") o.trace_file = next();
        else if (a == "--trace-from") o.trace_from = parse_num(next());
        else if (a == "--trace-to") o.trace_to = parse_num(next());
        else { fprintf(stderr, "unknown option %s (try --help)\n", a.c_str()); return false; }
    }
    return true;
}

// ---------------------------------------------------------------------------
// Machine configuration, as sharpmz.sv derives it from the OSD status bits.
// ---------------------------------------------------------------------------
struct ModelInfo { const char *name; uint8_t code; uint8_t display; };
static const ModelInfo MODELS[] = {
    {"mz80k", 0, 0}, {"mz80c", 1, 0}, {"mz1200", 2, 0}, {"mz80a", 3, 0},
    {"mz700", 4, 2}, {"mz800", 5, 2}, {"mz80b", 6, 1}, {"mz2000", 7, 1},
};

// sharpmz.sv mz_fast_tape(): menu step -> register value.
static uint8_t fast_tape_code(int step)
{
    static const uint8_t t[8] = {6, 0, 1, 2, 3, 4, 5, 6};
    return t[step & 7];
}

// ---------------------------------------------------------------------------
// Simulation
// ---------------------------------------------------------------------------
class Sim {
public:
    explicit Sim(const Options &o) : opt(o), top(new Vtop) {}

    int run();

private:
    const Options &opt;
    std::unique_ptr<Vtop> top;

    uint64_t cycle = 0;
    uint64_t cpu_cycles = 0;
    uint32_t frame = 0;
    bool     prev_vs = false, prev_hb = false, prev_m1 = true;
    int      exit_code = 0;

    // Video capture for the current frame.
    std::vector<uint8_t> line, fb;
    int fb_w = 0, fb_h = 0;

    // Keyboard.
    struct Ps2Event { uint16_t code; bool ext, press; };
    std::deque<Ps2Event> ps2_queue;
    std::multimap<uint32_t, Ps2Event> ps2_schedule;   // frame -> event
    uint64_t ps2_next_ok = 0;
    bool     ps2_toggle = false;

    FILE *flog = nullptr, *ftrace = nullptr;

    void clock();
    void on_frame_end();
    void write_config();
    void ioctl_write(uint32_t addr, uint8_t data);
    bool load_mzf(bool direct);
    void schedule_typing();
    void print_ascii();
    void dump_memory();
    bool want_png(uint32_t f) const;
    void write_png(uint32_t f);
};

void Sim::clock()
{
    // Sample what the video pipeline sees at this rising edge: MiSTer's
    // video_mixer latches RGB on the clk_sys edge where CE_PIXEL is high.
    top->clk_sys = 0;
    top->eval();
    bool ce = top->ce_pix;
    bool hb = top->VGA_HB, vb = top->VGA_VB, vs = top->VGA_VS;
    if (ce) {
        if (!hb && !vb) {
            line.push_back(top->VGA_R);
            line.push_back(top->VGA_G);
            line.push_back(top->VGA_B);
        }
        if (hb && !prev_hb && !line.empty()) {
            int w = (int)line.size() / 3;
            if (fb_h == 0) fb_w = w;
            line.resize((size_t)fb_w * 3, 0);
            fb.insert(fb.end(), line.begin(), line.end());
            fb_h++;
            line.clear();
        }
        prev_hb = hb;
    }

    top->clk_sys = 1;
    top->eval();
    cycle++;

    if (top->cpu_ce) cpu_cycles++;

    if (ftrace && frame >= opt.trace_from && frame <= opt.trace_to) {
        bool m1 = top->cpu_m1_n;
        if (!m1 && prev_m1) fprintf(ftrace, "%u,%llu,%04X\n", frame, (unsigned long long)cpu_cycles, top->cpu_pc);
        prev_m1 = m1;
    }

    // Keyboard: one PS/2 event at a time, spaced like hps_io delivers them.
    if (!ps2_queue.empty() && cycle >= ps2_next_ok) {
        Ps2Event e = ps2_queue.front();
        ps2_queue.pop_front();
        ps2_toggle = !ps2_toggle;
        top->ps2_key = (uint16_t)((ps2_toggle << 10) | (e.press << 9) | (e.ext << 8) | (e.code & 0xFF));
        ps2_next_ok = cycle + (uint64_t)(CLK_HZ / 2000);   // 0.5 ms
    }

    if (vs && !prev_vs) on_frame_end();
    prev_vs = vs;

    if (!opt.quiet && (cycle % (cycle < 1000 ? 50 : 10000000)) == 0)
        fprintf(stderr, "[sim] cycle %lluM  %.3fs emulated  frame %u  pc %04X  vs %d hb %d vb %d ce_pix %d  cpu_ce %llu sysreset %d delay %d rm %d warm %d wait_n %d vwait_n %d model %d vga %d vid %d cpu %d\n",
                (unsigned long long)(cycle / 1000000), cycle / CLK_HZ, frame, top->cpu_pc, vs, hb, vb, ce, (unsigned long long)cpu_cycles, top->dbg_sysreset, top->dbg_delay, top->dbg_rm, top->dbg_warm, top->dbg_wait_n, top->dbg_vwait_n,
                (int)(top->dbg_config[0] & 0xFF), (int)((top->dbg_config[0] >> 17) & 3), (int)(((top->dbg_config[1] >> 30) & 3) | ((top->dbg_config[2] & 1) << 2)), (int)((top->dbg_config[1] >> 26) & 15));
}

void Sim::on_frame_end()
{
    // Frame `frame` is complete.
    uint32_t h = 2166136261u;
    for (uint8_t b : fb) { h ^= b; h *= 16777619u; }
    if (flog) fprintf(flog, "%u,%08x,%llu,%04X\n", frame, h, (unsigned long long)cpu_cycles, top->cpu_pc);
    if (want_png(frame)) write_png(frame);
    if (!opt.quiet && frame % 50 == 0)
        fprintf(stderr, "[sim] frame %u  %dx%d  pc %04X  %.2fs emulated\n", frame, fb_w, fb_h, top->cpu_pc, cycle / CLK_HZ);

    fb.clear(); fb_h = 0; line.clear();
    frame++;

    auto range = ps2_schedule.equal_range(frame);
    for (auto it = range.first; it != range.second; ++it) ps2_queue.push_back(it->second);

    if (!opt.mzf.empty() && opt.mzf_direct && frame == opt.mzf_direct_frame && frame != 0) load_mzf(true);
}

void Sim::ioctl_write(uint32_t addr, uint8_t data)
{
    top->ioctl_addr = addr;
    top->ioctl_dout = data;
    top->ioctl_wr = 1;
    clock();
    top->ioctl_wr = 0;
    clock();
    clock();
}

void Sim::write_config()
{
    const ModelInfo *m = nullptr;
    for (auto &x : MODELS) if (opt.model == x.name) m = &x;
    top->cfg_model    = m->code;
    top->cfg_display  = m->display;                            // video/graphics/VRAM wait/PCG bits off
    top->cfg_display2 = opt.vmode == "native" ? 3 : 1;         // sharpmz.sv: 2'b11 native, 2'b01 640x480@60
    top->cfg_cpu      = (uint8_t)(opt.turbo & 7);
    top->cfg_audio    = 0;
    top->cfg_cmt      = (uint8_t)((3 << 3) | fast_tape_code(opt.fast_tape)); // buttons auto, fast tape
}

// Same address mapping as sharpmz.sv (mz_ioctl_addr_map).
bool Sim::load_mzf(bool direct)
{
    std::ifstream f(opt.mzf, std::ios::binary);
    std::vector<uint8_t> d((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
    if (d.size() < 128) { fprintf(stderr, "cannot read MZF '%s'\n", opt.mzf.c_str()); exit_code = 2; return false; }
    uint16_t size = d[18] | (d[19] << 8), load = d[20] | (d[21] << 8), exec = d[22] | (d[23] << 8);
    if (!opt.quiet)
        fprintf(stderr, "[sim] %s MZF '%s' size %04X load %04X exec %04X at frame %u\n",
                direct ? "direct-loading" : "loading tape", opt.mzf.c_str(), size, load, exec, frame);

    top->ioctl_download = 1;
    if (direct) top->warm_reset = 1;
    for (size_t i = 0; i < d.size(); i++) {
        uint32_t a;
        if (direct) {
            if (i >= 128 && size && i >= 128u + size) break;
            a = i < 128 ? 0x100000 + 0x10F0 + i : 0x100000 + load + (i - 128);
        } else {
            a = i < 128 ? 0x400000 + i : 0x410000 + (i - 128);
        }
        ioctl_write(a, d[i]);
    }
    top->ioctl_download = 0;
    for (int i = 0; i < 64; i++) clock();
    top->warm_reset = 0;
    return true;
}

// Expand --type commands into timed PS/2 events.
void Sim::schedule_typing()
{
    for (auto &t : opt.types) {
        uint32_t f = t.frame;
        const std::string &s = t.text;
        for (size_t i = 0; i < s.size(); i++) {
            Ps2Key k;
            bool ok = false;
            if (s[i] == '\\' && i + 1 < s.size()) {
                char c = s[++i];
                ok = ps2_from_ascii(c == 'n' || c == 'r' ? '\n' : c, k);
            } else if (s[i] == '{') {
                size_t e = s.find('}', i);
                std::string name = s.substr(i + 1, e - i - 1);
                i = e;
                if (name.rfind("WAIT", 0) == 0) { f += parse_num(name.substr(4)); continue; }
                ok = ps2_from_name(name, k);
                if (!ok) fprintf(stderr, "--type: unknown key {%s}\n", name.c_str());
            } else {
                ok = ps2_from_ascii(s[i], k);
                if (!ok) fprintf(stderr, "--type: no key for '%c'\n", s[i]);
            }
            if (!ok) continue;
            if (k.shift) ps2_schedule.insert({f, {PS2_LSHIFT, false, true}});
            ps2_schedule.insert({f, {k.code, k.extended, true}});
            ps2_schedule.insert({f + opt.type_press, {k.code, k.extended, false}});
            if (k.shift) ps2_schedule.insert({f + opt.type_press, {PS2_LSHIFT, false, false}});
            f += opt.type_press + opt.type_release;
        }
    }
}

bool Sim::want_png(uint32_t f) const
{
    if (opt.screenshots.count(f)) return true;
    if (opt.dump_range && f >= opt.dump_from && f <= opt.dump_to) return true;
    if (opt.dump_every && f % opt.dump_every == 0) return true;
    return false;
}

void Sim::write_png(uint32_t f)
{
    if (fb_w == 0 || fb_h == 0) return;
    char name[64];
    snprintf(name, sizeof(name), "%s/frame_%06u.png", opt.out_dir.c_str(), f);
    if (!stbi_write_png(name, fb_w, fb_h, 3, fb.data(), fb_w * 3)) {
        fprintf(stderr, "cannot write %s\n", name);
        exit_code = 3;
    }
}

void Sim::print_ascii()
{
    int cols = opt.ascii_cols;
    for (int row = 0; row < 25; row++) {
        std::string s;
        for (int col = 0; col < cols; col++) {
            // v1 video.vhd keeps character and attribute interleaved: even bytes are characters.
            top->vram_addr = (row * cols + col) * 2;
            top->eval();
            char c = sharp_vcode_ascii[top->vram_q];
            s += c ? c : '.';
        }
        while (!s.empty() && s.back() == ' ') s.pop_back();
        printf("%s\n", s.c_str());
    }
    fflush(stdout);
}

void Sim::dump_memory()
{
    for (auto &md : opt.memdumps) {
        std::vector<uint8_t> buf(md.len);
        for (uint32_t k = 0; k < md.len; k++) {
            top->sysram_addr = (md.addr + k) & 0xFFFF;
            top->eval();
            buf[k] = top->sysram_q;
        }
        FILE *f = fopen(md.path.c_str(), "wb");
        if (!f || fwrite(buf.data(), 1, buf.size(), f) != buf.size()) {
            fprintf(stderr, "--dump-mem: cannot write %s\n", md.path.c_str());
            exit_code = 3;
        }
        if (f) fclose(f);
    }
}

int Sim::run()
{
    bool known = false;
    for (auto &x : MODELS) if (opt.model == x.name) known = true;
    if (!known) { fprintf(stderr, "unknown model %s\n", opt.model.c_str()); return 2; }
    if (!opt.mzf.empty()) {
        struct stat st;
        if (stat(opt.mzf.c_str(), &st) != 0) { fprintf(stderr, "cannot open %s\n", opt.mzf.c_str()); return 2; }
    }
    mkdir(opt.out_dir.c_str(), 0777);
    if (!opt.frame_log.empty() && !(flog = fopen(opt.frame_log.c_str(), "w"))) {
        fprintf(stderr, "cannot write %s\n", opt.frame_log.c_str()); return 2;
    }
    if (flog) fprintf(flog, "frame,fb_hash,cpu_cycles,pc\n");
    if (!opt.trace_file.empty() && !(ftrace = fopen(opt.trace_file.c_str(), "w"))) {
        fprintf(stderr, "cannot write %s\n", opt.trace_file.c_str()); return 2;
    }
    if (ftrace) fprintf(ftrace, "frame,cpu_cycle,pc\n");

    // Power-on: hold reset, then configure the machine the way sharpmz.sv does.
    top->reset = 1;
    top->warm_reset = 0;
    top->ps2_key = 0;
    write_config();
    for (int i = 0; i < 256; i++) clock();
    top->reset = 0;
    for (int i = 0; i < 128; i++) clock();
    // Reset the frame count and counters so frame 0 starts with the configured machine.
    frame = 0; cpu_cycles = 0; fb.clear(); fb_h = 0; line.clear();

    schedule_typing();
    auto range = ps2_schedule.equal_range(0);
    for (auto it = range.first; it != range.second; ++it) ps2_queue.push_back(it->second);

    if (!opt.mzf.empty() && (!opt.mzf_direct || opt.mzf_direct_frame == 0))
        if (!load_mzf(opt.mzf_direct)) return exit_code;

    uint32_t last = opt.stop_set ? opt.stop_frame : 150;
    while (frame <= last && !Verilated::gotFinish()) clock();

    if (opt.ascii_end) print_ascii();
    dump_memory();
    if (flog) fclose(flog);
    if (ftrace) fclose(ftrace);
    return exit_code;
}

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    Options opt;
    if (!parse_args(argc, argv, opt)) return 2;
    Sim sim(opt);
    return sim.run();
}
