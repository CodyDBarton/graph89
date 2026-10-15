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
void graph89_retained_text_enable(int enabled);
int graph89_copy_retained_text(const uint8_t *screen, int32_t *packets, int capacity);
int graph89_copy_hd_plot_decorations(float *segments,int capacity);
void graph89_hd_plot_enable(int enabled,int samples);
void graph89_graph_cursor_speed(int multiplier);
int graph89_copy_hd_plot(const uint8_t *screen,float *points,int capacity,uint8_t *background);
int graph89_copy_font_templates(uint8_t *templates);
int graph89_save(const char *path);
int graph89_restore(const char *path);
int graph89_copy_camera(double *meta);
int graph89_copy_mesh(float *vertices,uint32_t *edges,double *meta,int previous_generation);
double graph89_rotation_time(void);
void graph89_smooth_rotation(int enabled);
void graph89_stop(void);
#ifdef __cplusplus
}
#endif
#endif
