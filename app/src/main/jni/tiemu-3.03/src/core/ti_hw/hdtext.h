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
   a retained pretty-print shape (189 integral, 40/41 parentheses). Font 4 denotes the Home/Y= XOR cursor; inverse holds an eight-row blink mask.
   Full-content packets (Home and Y=):
   5: expression header, code=group ID, inverse=selection, width=primitive count,
      attribute=Home alignment (0 unknown, 1 calculated output, 2 entered expression).
   6: full unclipped glyph, attribute=original font, clipLeft=group ID.
   7: line/pixel, code=x1, inverse=y1, width=attribute, clipLeft=group ID.
   8: editor header, x=cursor offset, y=ROM scroll offset, code=TE flags,
      inverse=selection start, width=full byte length, height=editor kind (0 Home, 1 Y=),
      attribute=editor identity, clipLeft/right=input bounds.
   9: editor character, x=byte index, code=ROM character.
   10: Y= equation-list marker; compact its labels/graphics with the expression groups.
   11: glyph from the extra Y= drawing rows, attribute=original font.
   Groups exceeding capture capacity are omitted whole. Returns packet count. */
/* Same export while caller holds the batch/snapshot lock. */
int hdtext_copy_locked(const uint8_t *pixels, int32_t *packets, int capacity);
int hdtext_copy(const uint8_t *pixels, int32_t *packets, int capacity);
#endif
