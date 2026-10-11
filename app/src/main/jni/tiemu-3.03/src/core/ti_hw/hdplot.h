#ifndef GRAPH89_HDPLOT_H
#define GRAPH89_HDPLOT_H
#include <stdint.h>
#include <stdio.h>
extern int hdplot_active;
extern unsigned char hdplot_pages[65536];
void hdplot_run_begin(void);
void hdplot_key_event(int key,int pressed);
int hdplot_trace_multiplier(void);
void hdplot_cursor_speed(int multiplier);
void hdplot_run_end(void);
void hdplot_observe(uint32_t pc);
void hdplot_reset(void);
int hdplot_pending(void);
void hdplot_save_pending(FILE *file);
void hdplot_load_pending(FILE *file);
void hdplot_enable(int enabled,int samples);
/* Original ink pixels in. Background bit 0 is ink; bit 1 preserves the
   current native LCD/text overlay above vectors; bit 2 protects cursor
   pixels from glyph replacement. Result: four exclusive
   clip bounds followed by unrounded LCD-coordinate x,y pairs; NaN breaks paths. */
int hdplot_copy(const uint8_t *pixels,float *points,int capacity,uint8_t *background);
/* Independent line segments: x0,y0,x1,y1 in centered LCD coordinates.
   A zero-length segment is a grid dot. NaN,kind,x,y denotes a live
   navigation overlay: kind -1 is the verified circle/cross cursor centre, -2 its blink-off phase;
   Kinds -3/-4 are the 21x21 held-arrow cursor visible/hidden phases.
   ASCII 48..57 is a 6x8 plot-number cell using the approved sharp font. Query only after a valid plot copy. */
int hdplot_copy_decorations(float *segments,int capacity);
#endif
