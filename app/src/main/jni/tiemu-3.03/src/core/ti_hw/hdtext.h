#ifndef GRAPH89_RETAINED_TEXT_H
#define GRAPH89_RETAINED_TEXT_H
#include <stdint.h>
/* CPU-owned state. Host access and CPU batches share the same short-lived lock. */
extern int hdtext_active;
extern unsigned char hdtext_pages[65536];
void hdtext_run_begin(void);
void hdtext_run_end(void);
void hdtext_observe(uint32_t pc);
void hdtext_enable(int enabled);
void hdtext_reset(void);
/* Logical monochrome pixels (0/1), 160x100. Packets are twelve int32s:
   x,y,font,ROM character,inverse,width,height,attribute,clip left,top,right,bottom (exclusive). Font 3 denotes
   a retained pretty-print shape (189 integral, 40/41 parentheses). Font 4 denotes the Home XOR cursor; inverse holds an eight-row blink mask. Returns packet count. */
/* Same export while caller holds the batch/snapshot lock. */
int hdtext_copy_locked(const uint8_t *pixels, int32_t *packets, int capacity);
int hdtext_copy(const uint8_t *pixels, int32_t *packets, int capacity);
#endif
