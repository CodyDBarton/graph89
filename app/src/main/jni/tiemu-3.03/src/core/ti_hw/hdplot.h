#ifndef GRAPH89_HDPLOT_H
#define GRAPH89_HDPLOT_H
#include <stdint.h>
#include <stdio.h>
extern int hdplot_active;
extern unsigned char hdplot_pages[65536];
void hdplot_run_begin(void);
void hdplot_run_end(void);
void hdplot_observe(uint32_t pc);
void hdplot_reset(void);
int hdplot_pending(void);
void hdplot_save_pending(FILE *file);
void hdplot_load_pending(FILE *file);
void hdplot_enable(int enabled,int samples);
/* Original ink pixels in, axes/background ink out. Result: four exclusive
   clip bounds followed by unrounded LCD-coordinate x,y pairs; NaN breaks paths. */
int hdplot_copy(const uint8_t *pixels,float *points,int capacity,uint8_t *background);
/* Independent line segments: x0,y0,x1,y1 in centered LCD coordinates.
   A zero-length segment is a grid dot. Query only after a valid plot copy. */
int hdplot_copy_decorations(float *segments,int capacity);
#endif
