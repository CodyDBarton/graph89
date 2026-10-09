#ifndef GRAPH89_CORE_H
#define GRAPH89_CORE_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
int graph89_start(const char *os_path, const char *image_path);
void graph89_run(int instructions);
int graph89_batch_size(int cpu_percent);
int graph89_is_busy(void);
int graph89_type_text(const char *text);
void graph89_key(int key, int pressed);
int graph89_screen_is_on(void);
void graph89_wake(void);
void graph89_copy_screen(uint8_t *pixels);
int graph89_copy_font_templates(uint8_t *templates);
int graph89_save(const char *path);
int graph89_restore(const char *path);
void graph89_stop(void);
#ifdef __cplusplus
}
#endif
#endif
