#include "Graph89Core.h"
#include "ti68k_int.h"
#include "ti68k_def.h"
#include "images.h"
#include "m68k.h"
#include "kbd.h"
#include "state.h"
#include "engine.h"
#include "hdtext.h"
#include <stdio.h>
#include <string.h>

int graph89_start(const char *os_path, const char *image_path) {
    int type = 0;
    ti68k_config_load_default();
    int result = ti68k_convert_tib_to_image(os_path, image_path, -1, &type);
    if (result) return result;
    if (type != TI89t) return -89;
    result = ti68k_load_image(image_path);
    if (result) return result;
    result = ti68k_init();
    if (result) return result;
    return ti68k_reset();
}
void graph89_run(int instructions) { hw_m68k_run(instructions); }
int graph89_batch_size(int cpu_percent) {
    if (cpu_percent < 30) cpu_percent = 30;
    if (cpu_percent > 250) cpu_percent = 250;
    return (engine_num_cycles_per_loop() * cpu_percent / 100) / 4;
}
int graph89_is_busy(void) {
    // Same bottom-right LCD pixel used by the Android TiEmu wrapper.
    return tihw.on_off && (tihw.ram[tihw.lcd_adr + 99 * 30 + 19] & 1);
}
int graph89_type_text(const char *text) { return ti68k_kbd_push_chars(text); }
void graph89_key(int key, int pressed) { ti68k_kbd_set_key(key, pressed); }
int graph89_screen_is_on(void) { return tihw.on_off != 0; }
void graph89_wake(void) {
    if (tihw.on_off) return;
    ti68k_kbd_set_key(TIKEY_ON, 1);
    hw_m68k_run(400000);
    ti68k_kbd_set_key(TIKEY_ON, 0);
    hw_m68k_run(400000);
}
void graph89_copy_screen(uint8_t *pixels) {
    for (int y=0; y<100; y++) for (int x=0; x<160; x++) {
        pixels[y*160+x] = tihw.on_off && (tihw.ram[tihw.lcd_adr + y*30 + x/8] & (0x80 >> (x%8))) ? 30 : 210;
    }
}
int graph89_save(const char *path) { return ti68k_state_save(path); }
int graph89_restore(const char *path) { return ti68k_state_load(path); }
void graph89_stop(void) { ti68k_exit(); }

static unsigned int font_be32(const unsigned char *p) {
    return ((unsigned int)p[0]<<24)|((unsigned int)p[1]<<16)|((unsigned int)p[2]<<8)|p[3];
}
int graph89_copy_font_templates(uint8_t *templates) {
    unsigned int pos, offsets[3];
    unsigned char result[3 * 256 * 12];
    int f, c, row;
    if (!tihw.rom) return 0;
    if ((tihw.calc_type != TI89 && tihw.calc_type != TI89t)
        || tihw.rom_size < 2560) return 0;
    for (pos = 0; pos + 24 <= (unsigned int)tihw.rom_size; pos += 2)
    {
        const unsigned char *p = tihw.rom + pos;
        if (font_be32(p) != 0x300 || font_be32(p + 8) != 0x301
            || font_be32(p + 16) != 0x302) continue;
        for (f = 0; f < 3; ++f)
        {
            unsigned int address = font_be32(p + f * 8 + 4);
            int stride = f == 0 ? 6 : (f == 1 ? 8 : 10);
            if (address < tihw.rom_base) break;
            offsets[f] = address - tihw.rom_base;
            if (offsets[f] > (unsigned int)tihw.rom_size - 256 * stride) break;
            /* Validate printable characters and the space before trusting a table. */
            for (c = 32; c < 127; ++c)
            {
                const unsigned char *g = tihw.rom + offsets[f] + c * stride;
                if (f == 0 && (g[0] < 1 || g[0] > 8)) break;
                if (c == 32)
                    for (row = (f == 0); row < stride; ++row)
                        if (g[row]) break;
                if (c == 32 && row < stride) break;
            }
            if (c != 127) break;
        }
        if (f != 3) continue;
        memset(result, 0, sizeof(result));
        for (f = 0; f < 3; ++f)
            for (c = 0; c < 256; ++c)
            {
                int stride = f == 0 ? 6 : (f == 1 ? 8 : 10);
                const unsigned char *g = tihw.rom + offsets[f] + c * stride;
                unsigned char *out = result + (f * 256 + c) * 12;
                out[0] = f == 0 ? g[0] : (f == 1 ? 6 : 8);
                out[1] = f == 0 ? 5 : stride;
                for (row = 0; row < out[1]; ++row)
                    out[2 + row] = f == 2 ? g[row] : g[row + (f == 0)] << 1;
            }
        memcpy(templates, result, sizeof(result));
        return sizeof(result);
    }
    return 0;
}

void graph89_retained_text_enable(int enabled) { hdtext_enable(enabled); }
int graph89_copy_retained_text(const uint8_t *screen, int32_t *packets, int capacity) {
    uint8_t pixels[16000];
    for(int i=0;i<16000;i++) pixels[i]=screen[i]==30;
    return hdtext_copy(pixels, packets, capacity);
}
