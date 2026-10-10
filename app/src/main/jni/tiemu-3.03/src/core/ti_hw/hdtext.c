/* Retained identities from TI-68k drawing calls. No guest state is modified. */
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include "ti68k_def.h"
#include "libuae.h"
#include "hdtext.h"

#define MAX_CELLS 1024
#define MAX_SAVES 8
#define MAX_PORTS 8
#define LCD_PORT 0x4c00
#define PACKET_SIZE 12

typedef struct { int x,y,font,code,attr,left,top,right,bottom,w,h,pending; } Cell;
typedef struct { uint32_t address; int count; Cell cells[MAX_CELLS]; } Port;
typedef struct { uint32_t address; int w,h,count; uint8_t bitmap[3840]; Cell cells[MAX_CELLS]; } Saved;
int hdtext_active;
unsigned char hdtext_pages[65536];
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static Port ports[MAX_PORTS];
static Saved saves[MAX_SAVES];
static int next_save, ready;
static uint32_t font_slot,port_slot,font_offsets[3];
static uint32_t shape_sites[3],shape_finish,window_slot;
static uint32_t draw_char,draw_clip,draw_str,bitmap_get,bitmap_put,scroll,shift,clear;

static int byte_at(uint32_t a) {
    if(tihw.ram && a<tihw.ram_size) return tihw.ram[a];
    if(tihw.rom && a>=tihw.rom_base && a-tihw.rom_base<tihw.rom_size) return tihw.rom[a-tihw.rom_base];
    return -1;
}
static unsigned word_at(uint32_t a) { int h=byte_at(a),l=byte_at(a+1);return h<0||l<0?0:((unsigned)h<<8)|l; }
static uint32_t long_at(uint32_t a) { return (word_at(a)<<16)|word_at(a+2); }
static uint32_t rom_call(unsigned id) {
    uint32_t table=long_at(tihw.rom_base+0x12150);
    if(table<tihw.rom_base || table-tihw.rom_base>=tihw.rom_size || id>=long_at(table-4))return 0;
    uint32_t a=long_at(table+4*id);
    return a>=tihw.rom_base && a-tihw.rom_base<tihw.rom_size ? a:0;
}
static void watch(uint32_t a) { if(a)hdtext_pages[(a&0xffffff)>>8]=1; }
static void initialize(void) {
    if(ready || !tihw.rom || (tihw.calc_type!=TI89 && tihw.calc_type!=TI89t))return;
    ready=1;
    uint32_t f=rom_call(0x18e),p=rom_call(0x1a3);
    if(word_at(f)!=0x1039 || word_at(f+6)!=0x4e75 || word_at(p)!=0x23fc || long_at(p+2)!=LCD_PORT)return;
    font_slot=long_at(f+2);port_slot=long_at(p+6);
    if(font_slot>=tihw.ram_size || port_slot+4>tihw.ram_size){font_slot=port_slot=0;return;}
    for(uint32_t pos=0;pos+24<tihw.rom_size;pos+=2) {
        uint32_t a=tihw.rom_base+pos;
        if(long_at(a)!=0x300 || long_at(a+8)!=0x301 || long_at(a+16)!=0x302)continue;
        int valid=1;
        for(int f=0;f<3;f++) {
            uint32_t v=long_at(a+f*8+4);int stride=f==0?6:(f==1?8:10);
            if(v<tihw.rom_base || v-tihw.rom_base>tihw.rom_size-256*stride){valid=0;break;}
            font_offsets[f]=v;
            for(int c=32;c<127;c++) {
                uint32_t g=v+c*stride;
                if(f==0 && (byte_at(g)<1 || byte_at(g)>8)){valid=0;break;}
                if(c==32)for(int row=(f==0);row<stride;row++)if(byte_at(g+row)!=0){valid=0;break;}
            }
        }
        if(valid)break;
        memset(font_offsets,0,sizeof(font_offsets));
    }
    if(!font_offsets[0])return;
    draw_char=rom_call(0x1a4);draw_clip=rom_call(0x191);draw_str=rom_call(0x1a9);
    bitmap_get=rom_call(0x185);bitmap_put=rom_call(0x187);
    scroll=rom_call(0x18b);shift=rom_call(0x18c);clear=rom_call(0x19e);
    /* Verified pretty-print instruction sequences, not fixed ROM addresses.
       D3/D4 contain window-relative geometry and A2 the layout record. All
       three sites must agree on the window global; unknown ROMs fall back. */
    const uint16_t prefix[3][7]={{0x3404,0x5242,0x3e82,0x3403,0x5342,0x3f02,0x2f39},
        {0x3404,0x5342,0x3e82,0x3403,0x5242,0x3f02,0x2f39},
        {0x3404,0x5542,0x3e82,0x3f03,0x2f39}};
    const uint16_t suffix[3][5]={{0x3e84,0x3403,0x5542,0x3f02,0x2f39},
        {0x3404,0x5542,0x3e82,0x3403,0x5442},
        {0x3404,0x5342,0x3e82,0x3403,0x5242}};
    int found[3]={0};memset(shape_sites,0,sizeof(shape_sites));window_slot=0;
    for(uint32_t pos=0;pos+40<tihw.rom_size;pos+=2)for(int k=0;k<3;k++) {
        uint32_t a=tihw.rom_base+pos;int ok=1,n=k==2?5:7;
        for(int j=0;j<n;j++)if(word_at(a+j*2)!=prefix[k][j]){ok=0;break;}
        if(!ok || word_at(a+n*2+4)!=0x4eb9)continue;
        for(int j=0;j<5;j++)if(word_at(a+n*2+10+j*2)!=suffix[k][j]){ok=0;break;}
        if(!ok)continue;
        uint32_t slot=long_at(a+n*2);
        if(!slot || slot+4>tihw.ram_size || (window_slot && slot!=window_slot))continue;
        found[k]++;shape_sites[k]=a;window_slot=slot;
    }
    if(found[0]!=1 || found[1]!=1 || found[2]!=1)memset(shape_sites,0,sizeof(shape_sites));
    shape_finish=0;
    for(int k=0;k<3;k++)if(shape_sites[k]) {
        uint32_t target=0;
        for(uint32_t a=shape_sites[k]+24;a<shape_sites[k]+220;a+=2)
            if(long_at(a)==0x41eafff5 && word_at(a+4)==0x6000){target=a+6+(short)word_at(a+6);break;}
        if(!target || (shape_finish && shape_finish!=target)){memset(shape_sites,0,sizeof(shape_sites));shape_finish=0;break;}
        shape_finish=target;
    }
    watch(shape_finish);
    for(int k=0;k<3;k++)watch(shape_sites[k]);
    uint32_t addresses[]={draw_char,draw_clip,draw_str,bitmap_get,bitmap_put,scroll,shift,clear};
    for(unsigned i=0;i<sizeof(addresses)/sizeof(addresses[0]);i++)watch(addresses[i]);
}
static Port *port_for(uint32_t address,int create) {
    for(int i=0;i<MAX_PORTS;i++)if(ports[i].address==address)return &ports[i];
    if(create)for(int i=0;i<MAX_PORTS;i++)if(!ports[i].address){ports[i].address=address;return &ports[i];}
    return NULL; /* Unknown/excess off-screen surfaces use the pixel fallback. */
}
static int width_of(int f,int c) { return f==0?byte_at(font_offsets[0]+c*6):f==1?6:8; }
static int height_of(int f) { return f==0?5:f==1?8:10; }
static Cell character(int x,int y,int font,int code,int attr) {
    return (Cell){x,y,font,code,attr,0,0,240,128,width_of(font,code),height_of(font)};
}
static int visible(Cell c,int x,int y) {
    return x>=0 && x<160 && y>=0 && y<100 && x>=c.left && x<c.right && y>=c.top && y<c.bottom;
}
static int overlaps(Cell a,Cell b) {
    int al=a.x>a.left?a.x:a.left,at=a.y>a.top?a.y:a.top;
    int ar=a.x+a.w<a.right?a.x+a.w:a.right,ab=a.y+a.h<a.bottom?a.y+a.h:a.bottom;
    int bl=b.x>b.left?b.x:b.left,bt=b.y>b.top?b.y:b.top;
    int br=b.x+b.w<b.right?b.x+b.w:b.right,bb=b.y+b.h<b.bottom?b.y+b.h:b.bottom;
    return al<br && bl<ar && at<bb && bt<ab;
}
static void insert(Port *p,Cell c) {
    if(!p || c.font<0 || c.font>3 || c.code<0 || c.code>255)return;
    int w=c.w,h=c.h;
    if(w<1 || w>8 || h<1 || h>512 || c.x+w<=c.left || c.y+h<=c.top || c.x>=c.right || c.y>=c.bottom)return;
    for(int i=0;i<p->count;) {
        if(overlaps(p->cells[i],c))p->cells[i]=p->cells[--p->count];else i++;
    }
    if(c.code!=32 && p->count<MAX_CELLS)p->cells[p->count++]=c;
}
static int inside(Cell c,int x,int y,int w,int h) {
    return c.x>=x && c.y>=y && c.x+c.w<=x+w && c.y+c.h<=y+h;
}
static int same_bitmap(const Saved *s,uint32_t buffer) {
    if(word_at(buffer)!=s->h || word_at(buffer+2)!=s->w)return 0;
    int stride=(s->w+7)/8;
    for(int y=0;y<s->h;y++)for(int x=0;x<stride;x++) {
        int b=byte_at(buffer+4+y*stride+x);if(b<0)return 0;
        int mask=x==stride-1 && (s->w&7) ? (255 << (8-(s->w&7)))&255:255;
        if((b&mask)!=(s->bitmap[y*stride+x]&mask))return 0;
    }
    return 1;
}
void hdtext_observe(uint32_t pc) {
    if(!font_slot || !port_slot || !font_offsets[0])return;
    int font=byte_at(font_slot);if(font<0 || font>2)return;
    uint32_t address=long_at(port_slot),a=m68k_areg(regs,7)+4;
    Port *p=port_for(address,1);if(!p)return;
    if(shape_finish && pc==shape_finish) {
        for(int i=0;i<p->count;i++)p->cells[i].pending=0;
        return;
    }
    for(int k=0;k<3;k++)if(shape_sites[k] && pc==shape_sites[k]) {
        uint32_t expr=m68k_areg(regs,2),win=long_at(window_slot);
        if(expr<8 || expr>=tihw.ram_size || win+28>tihw.ram_size)return;
        int h=(byte_at(expr-6)|(byte_at(expr-5)<<8))+(byte_at(expr-8)|(byte_at(expr-7)<<8));
        int x=(short)m68k_dreg(regs,3),y=(short)m68k_dreg(regs,4);
        if(k==0){x-=2;y-=h-2;}else {y-=2;}
        x+=byte_at(win+16);y+=byte_at(win+17);
        Cell c={x,y,3,k==0?189:k==1?40:41,1,byte_at(win+24),byte_at(win+25),byte_at(win+26)+1,byte_at(win+27)+1,k==0?5:3,h,1};
        if(h>=7)insert(p,c);return;
    }
    if(pc==draw_char || pc==draw_clip) {
        Cell c=character((short)word_at(a),(short)word_at(a+2),font,word_at(a+4)&255,(short)word_at(a+(pc==draw_clip?10:6)));
        if(pc==draw_clip) {
            uint32_t clip=long_at(a+6);int x=byte_at(clip),y=byte_at(clip+1),right=byte_at(clip+2),bottom=byte_at(clip+3);
            if(x<0 || y<0 || right<x || bottom<y)return;
            c.left=x;c.top=y;c.right=right+1;c.bottom=bottom+1;
        }
        insert(p,c);
    } else if(pc==draw_str) {
        int x=(short)word_at(a),y=(short)word_at(a+2),attr=(short)word_at(a+8);uint32_t s=long_at(a+4);
        for(int i=0;i<256;i++) { int c=byte_at(s+i);if(c<=0)break;insert(p,character(x,y,font,c,attr));x+=width_of(font,c); }
    } else if(pc==clear) {
        p->count=0;
    } else if(pc==bitmap_get) {
        uint32_t r=long_at(a),buffer=long_at(a+4);int x=byte_at(r),y=byte_at(r+1),right=byte_at(r+2),bottom=byte_at(r+3);
        if(x<0 || y<0 || right<x || bottom<y || right>=240 || bottom>=128 || address!=tihw.lcd_adr)return;
        Saved *s=NULL;for(int i=0;i<MAX_SAVES;i++)if(saves[i].address==buffer){s=&saves[i];break;}
        if(!s)s=&saves[next_save++%MAX_SAVES];
        s->address=buffer;s->w=right-x+1;s->h=bottom-y+1;s->count=0;
        memset(s->bitmap,0,sizeof(s->bitmap));int stride=(s->w+7)/8;
        for(int row=0;row<s->h;row++)for(int column=0;column<s->w;column++) {
            int b=byte_at(address+(y+row)*30+(x+column)/8);
            if(b>=0 && (b&(0x80>>((x+column)&7))))s->bitmap[row*stride+column/8]|=0x80>>(column&7);
        }
        for(int i=0;i<p->count;i++)if(overlaps(p->cells[i],(Cell){.x=x,.y=y,.w=s->w,.h=s->h,.left=x,.top=y,.right=right+1,.bottom=bottom+1})) {
            Cell c=p->cells[i];c.left=c.left>x?c.left:x;c.top=c.top>y?c.top:y;
            c.right=c.right<right+1?c.right:right+1;c.bottom=c.bottom<bottom+1?c.bottom:bottom+1;
            c.x-=x;c.y-=y;c.left-=x;c.right-=x;c.top-=y;c.bottom-=y;s->cells[s->count++]=c;
        }
    } else if(pc==bitmap_put) {
        int x=(short)word_at(a),y=(short)word_at(a+2),attr=(short)word_at(a+12);uint32_t buffer=long_at(a+4);
        if(attr!=4 && attr!=1 && attr!=0)return; /* Replace/normal/reverse only. */
        for(int i=0;i<MAX_SAVES;i++)if(saves[i].address && same_bitmap(&saves[i],buffer)) {
            for(int j=0;j<saves[i].count;j++){Cell c=saves[i].cells[j];c.x+=x;c.y+=y;c.left+=x;c.right+=x;c.top+=y;c.bottom+=y;insert(p,c);}break;
        }
    } else if(pc==scroll || pc==shift) {
        uint32_t r=long_at(a);int x=byte_at(r),y=byte_at(r+1),right=byte_at(r+2),bottom=byte_at(r+3),n=(short)word_at(a+8);
        /* Signed amount is validated against the final LCD; unsupported clipping
           or OS-specific direction simply leaves those cells to the fallback. */
        for(int i=0;i<p->count;i++)if(inside(p->cells[i],x,y,right-x+1,bottom-y+1)) {
            if(pc==scroll)p->cells[i].y-=n;else p->cells[i].x-=n;
        }
    }
}
void hdtext_run_begin(void) { pthread_mutex_lock(&lock);if(hdtext_active)initialize(); }
void hdtext_run_end(void) { pthread_mutex_unlock(&lock); }
void hdtext_enable(int enabled) {
    pthread_mutex_lock(&lock);
    if(hdtext_active!=(enabled!=0)){memset(ports,0,sizeof(ports));memset(saves,0,sizeof(saves));}
    hdtext_active=enabled!=0;pthread_mutex_unlock(&lock);
}
void hdtext_reset(void) {
    pthread_mutex_lock(&lock);ready=0;font_slot=port_slot=window_slot=shape_finish=0;memset(shape_sites,0,sizeof(shape_sites));memset(font_offsets,0,sizeof(font_offsets));
    memset(hdtext_pages,0,sizeof(hdtext_pages));memset(ports,0,sizeof(ports));memset(saves,0,sizeof(saves));next_save=0;
    pthread_mutex_unlock(&lock);
}
static int matches(Cell c,const uint8_t *pixels,int inverse) {
    int w=c.w,h=c.h,stride=c.font==0?6:h;
    int origin=c.x+(c.font<2);
    int ink=0,rows[512],left=w,right=-1,top=h,bottom=-1;
    for(int y=0;y<h;y++) {
        if(c.font==3) {
            int cap=c.code==189?2:c.code==40?1:4,stem=c.code==189?4:c.code==40?4:1;
            int r=y==0 || y==h-1?cap:y==1 || y==h-2?2:stem;
            if(c.code==189)r=y==0?2:y==1?5:y==h-2?20:y==h-1?8:4;
            rows[y]=r<<(8-w);
        } else {
            rows[y]=byte_at(font_offsets[c.font]+c.code*stride+y+(c.font==0));
            if(c.font!=2)rows[y]<<=1;
        }
        for(int x=0;x<w;x++)if((rows[y]>>(7-x))&1) {
            ink++;if(x<left)left=x;if(x>right)right=x;if(y<top)top=y;if(y>bottom)bottom=y;
        }
    }
    int foreground=0,background=0,visible_ink=0;
    for(int y=0;y<h;y++)for(int x=0;x<w;x++) {
        if(!visible(c,origin+x,c.y+y))continue;
        if((rows[y]>>(7-x))&1)visible_ink++;
        if(pixels[(c.y+y)*160+origin+x])foreground++;else background++;
    }
    if(!foreground || !background || !visible_ink)return 0; /* A cleared/solid region is not text. */
    int cursor_column=-1;
    for(int y=0;y<h;y++)for(int x=0;x<w;x++) {
        if(!visible(c,origin+x,c.y+y))continue;
        int expected=(rows[y]>>(7-x))&1;
        int actual=(pixels[(c.y+y)*160+origin+x]!=0)^inverse;
        if(actual==expected)continue;
        if(expected || (x>=left && x<=right && y>=top && y<=bottom))return 0;
        /* Permit only the ROM's solid cursor column/underline in blank padding.
           Arbitrary new drawing invalidates this identity. */
        int cursor=x<left || x>right;
        if(cursor)for(int j=0;j<h;j++)if(visible(c,origin+x,c.y+j) && ((pixels[(c.y+j)*160+origin+x]!=0)^inverse)==0){cursor=0;break;}
        if(cursor) {
            if(cursor_column>=0 && cursor_column!=x)return 0;
            cursor_column=x;
        }
        if(!cursor && y==h-1 && y>bottom) {
            cursor=1;
            for(int j=0;j<w;j++)if(visible(c,origin+j,c.y+y) && ((pixels[(c.y+y)*160+origin+j]!=0)^inverse)==0){cursor=0;break;}
        }
        if(!cursor)return 0;
    }
    return ink>0;
}
int hdtext_copy_locked(const uint8_t *pixels,int32_t *out,int capacity) {
    int count=0;
    Port *p=port_for(tihw.lcd_adr,0);
    if(!p && tihw.lcd_adr==LCD_PORT)p=port_for(LCD_PORT,0);
    if(hdtext_active && tihw.on_off && font_offsets[0] && p)for(int i=0;i<p->count;) {
        Cell c=p->cells[i];int inv=matches(c,pixels,0)?0:matches(c,pixels,1)?1:-1;
        if(inv<0){
            /* A host frame may fall between the ROM's stem and cap calls.
               Keep an unfinished shape until the common layout continuation,
               without exporting any pixels that have not yet validated. */
            if(c.pending){i++;continue;}
            p->cells[i]=p->cells[--p->count];continue;
        }
        i++;
        if(c.attr==3)continue; /* Shaded glyphs intentionally stay original. */
        if(count<capacity){int32_t *v=out+count*PACKET_SIZE;v[0]=c.x+(c.font<2);v[1]=c.y;v[2]=c.font;v[3]=c.code;v[4]=inv;v[5]=c.w;v[6]=c.h;v[7]=c.attr;v[8]=c.left<0?0:c.left;v[9]=c.top<0?0:c.top;v[10]=c.right>160?160:c.right;v[11]=c.bottom>100?100:c.bottom;count++;}
    }
    return count;
}
int hdtext_copy(const uint8_t *pixels,int32_t *out,int capacity) {
    pthread_mutex_lock(&lock);
    int count=hdtext_copy_locked(pixels,out,capacity);
    pthread_mutex_unlock(&lock);return count;
}
