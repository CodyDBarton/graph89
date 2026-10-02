#include "Graph89Core.h"
#include "ti68k_int.h"
#include "ti68k_def.h"
#include "images.h"
#include "m68k.h"
#include "kbd.h"
#include "state.h"
#include "engine.h"
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
