/* Retained TI-68k drawing identities, including bounded extra Y= layout rows. */
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
typedef struct { uint32_t address; int count,cursor_x,cursor_valid; Cell cells[MAX_CELLS]; } Port;
typedef struct { uint32_t address; int w,h,count; uint8_t bitmap[3840]; Cell cells[MAX_CELLS]; } Saved;
int hdtext_active;
unsigned char hdtext_pages[65536];
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static Port ports[MAX_PORTS];
static Saved saves[MAX_SAVES];
typedef struct { int kind,x,y,x1,y1,font,code,w,h,attr; } Primitive;
typedef struct { uint32_t return_pc;int count,complete;Primitive items[512]; } Expression;
static Expression expressions[16];static int expression_next,expression_active=-1;
static uint32_t editor,heap_slot,print_expr,clip_line,draw_pix,win_clear,te_calls[5];
static int next_save, ready;
static uint32_t y_list_start,y_list_finish;
static int y_capture,y_complete,y_extra_count;
static Cell y_extra[128];
static uint32_t font_slot,port_slot,font_offsets[3];
static uint32_t shape_sites[3],shape_finish,window_slot;
static uint32_t draw_char,draw_clip,draw_str,bitmap_get,bitmap_put,scroll,shift,clear,rect_fill;

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
    uint32_t heap=rom_call(0x96);
    if(word_at(heap)==0x7000 && word_at(heap+2)==0x302f && word_at(heap+4)==4 && word_at(heap+6)==0xe588 && word_at(heap+8)==0x2079 && word_at(heap+14)==0x2070 && word_at(heap+16)==0x0800 && word_at(heap+18)==0x4e75)heap_slot=long_at(heap+10);
    print_expr=rom_call(0x4c);clip_line=rom_call(0x193);draw_pix=rom_call(0x1a8);win_clear=rom_call(0x0c);
    int ids[5]={0xa8,0xa9,0xac,0xb1,0xb3};for(int i=0;i<5;i++){te_calls[i]=rom_call(ids[i]);watch(te_calls[i]);}
    draw_char=rom_call(0x1a4);draw_clip=rom_call(0x191);draw_str=rom_call(0x1a9);
    bitmap_get=rom_call(0x185);bitmap_put=rom_call(0x187);
    scroll=rom_call(0x18b);shift=rom_call(0x18c);clear=rom_call(0x19e);rect_fill=rom_call(0x189);
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
    /* Verified Y= paint-loop signature: WinHeight result in D6, selected row
       geometry in the sheet at offsets 2A0/2A2. Extending only its local drawing
       limit asks AMS to lay out extra real rows; its LCD clip remains unchanged. */
    y_list_start=y_list_finish=0;int y_found=0;
    for(uint32_t pos=0;pos+20<tihw.rom_size;pos+=2) {
        uint32_t a=tihw.rom_base+pos;
        if(long_at(a)!=0x3c00362a || long_at(a+4)!=0x02a23d6a || long_at(a+8)!=0x02a0ffe2 || long_at(a+12)!=0x3d6a02a8 || word_at(a+16)!=0xffe0)continue;
        for(uint32_t end=a+300;end<a+600;end+=2)if(long_at(end)==0x4cee1c78 && long_at(end+4)==0xffe44e5e && word_at(end+8)==0x4e75) {
            y_found++;y_list_start=a+2;y_list_finish=end;break;
        }
    }
    if(y_found!=1)y_list_start=y_list_finish=0;
    watch(y_list_start);watch(y_list_finish);
    watch(shape_finish);
    for(int k=0;k<3;k++)watch(shape_sites[k]);
    uint32_t addresses[]={draw_char,draw_clip,draw_str,bitmap_get,bitmap_put,scroll,shift,clear,rect_fill,print_expr,clip_line,draw_pix,win_clear};
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
static void remember_primitive(Primitive item) {
    if(expression_active>=0) {
        Expression *e=&expressions[expression_active];
        if(e->count<512)e->items[e->count++]=item;else e->complete=-1;
    }
}
void hdtext_observe(uint32_t pc) {
    if(!font_slot || !port_slot || !font_offsets[0])return;
    int font=byte_at(font_slot);if(font<0 || font>2)return;
    uint32_t address=long_at(port_slot),a=m68k_areg(regs,7)+4;
    Port *p=port_for(address,1);if(!p)return;
    if(pc==y_list_start) {
        uint32_t sheet=m68k_areg(regs,2),win=m68k_areg(regs,3);
        y_capture=win==sheet+0x252 && win+28<tihw.ram_size && byte_at(win+16)==0 && byte_at(win+17)==16 && byte_at(win+18)==159 && byte_at(win+19)==82;
        y_complete=0;y_extra_count=0;
        if(y_capture && (m68k_dreg(regs,6)&65535)==67)
            m68k_dreg(regs,6)=(m68k_dreg(regs,6)&0xffff0000)|93;
    }
    if(pc==y_list_finish && y_capture){y_capture=0;y_complete=1;}
    if(expression_active>=0 && expressions[expression_active].return_pc==pc) {
        Expression *e=&expressions[expression_active];if(e->complete>=0)e->complete=1;expression_active=-1;
    }
    for(int i=0;i<5;i++)if(pc==te_calls[i]) {
        uint32_t te=long_at(a),parent=long_at(te);
        if(te+38<tihw.ram_size && parent+28<tihw.ram_size && byte_at(parent+17)==83 && word_at(te+8)==2 && word_at(te+12)==9)editor=te;
    }
    if(pc==win_clear) {
        uint32_t win=long_at(a);
        /* Preserve entry/status/toolbar clears; a body clear or dialog must
           invalidate compact history so it cannot paint over the new window. */
        if(win<tihw.ram_size && win+28<tihw.ram_size && byte_at(win+17)<83 && byte_at(win+19)>=16) {
            memset(expressions,0,sizeof(expressions));expression_active=-1;expression_next=0;y_complete=0;y_extra_count=0;
        }
    }
    if(pc==print_expr && expression_active<0) {
        uint32_t win=long_at(a+4);
        if(win+28<tihw.ram_size && byte_at(win+17)==16 && byte_at(win+16)==0 && byte_at(win+18)==159) {
            int slot=expression_next++%16;Expression *e=&expressions[slot];memset(e,0,sizeof *e);
            e->return_pc=long_at(a-4);watch(e->return_pc);expression_active=slot;
        }
    }
    if(pc==clip_line && expression_active>=0) {
        uint32_t r=long_at(a);remember_primitive((Primitive){.kind=1,.x=(short)word_at(r),.y=(short)word_at(r+2),.x1=(short)word_at(r+4),.y1=(short)word_at(r+6),.attr=(short)word_at(a+8)});
    }
    if(pc==draw_pix && expression_active>=0)remember_primitive((Primitive){.kind=1,.x=(short)word_at(a),.y=(short)word_at(a+2),.x1=(short)word_at(a),.y1=(short)word_at(a+2),.attr=(short)word_at(a+4)});
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
        if(h>512 && expression_active>=0)expressions[expression_active].complete=-1;
        if(h>=7 && h<=512){remember_primitive((Primitive){.x=c.x,.y=c.y,.font=3,.code=c.code,.w=c.w,.h=c.h,.attr=c.attr});insert(p,c);}return;
    }
    if(pc==rect_fill) {
        uint32_t r=long_at(a);int x=byte_at(r),y=byte_at(r+1),right=byte_at(r+2),bottom=byte_at(r+3),attr=(short)word_at(a+8);
        if(y<=92 && bottom>=85) {
            p->cursor_valid=font==1 && address==tihw.lcd_adr && y==85 && bottom==92 && right==x+1 && x%6==0 && x+1<160 && attr==2;
            if(p->cursor_valid)p->cursor_x=x;
        }
        return;
    }
    if(pc==draw_char || pc==draw_clip) {
        Cell c=character((short)word_at(a),(short)word_at(a+2),font,word_at(a+4)&255,(short)word_at(a+(pc==draw_clip?10:6)));
        if(pc==draw_clip) {
            uint32_t clip=long_at(a+6);int x=byte_at(clip),y=byte_at(clip+1),right=byte_at(clip+2),bottom=byte_at(clip+3);
            if(x<0 || y<0 || right<x || bottom<y)return;
            c.left=x;c.top=y;c.right=right+1;c.bottom=bottom+1;
        }
        remember_primitive((Primitive){.x=c.x+(c.font<2),.y=c.y,.font=c.font,.code=c.code,.w=c.w,.h=c.h,.attr=c.attr});
        if(y_capture && expression_active<0 && address==tihw.lcd_adr && c.y>=83 && y_extra_count<128)y_extra[y_extra_count++]=c;
        insert(p,c);
    } else if(pc==draw_str) {
        int x=(short)word_at(a),y=(short)word_at(a+2),attr=(short)word_at(a+8);uint32_t s=long_at(a+4);
        for(int i=0;i<256;i++) { int c=byte_at(s+i);if(c<=0)break;insert(p,character(x,y,font,c,attr));x+=width_of(font,c); }
    } else if(pc==clear) {
        p->count=0;p->cursor_valid=0;
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
    if(hdtext_active!=(enabled!=0)){memset(ports,0,sizeof(ports));memset(saves,0,sizeof(saves));editor=0;y_capture=y_complete=y_extra_count=0;expression_active=-1;expression_next=0;memset(expressions,0,sizeof(expressions));}
    hdtext_active=enabled!=0;pthread_mutex_unlock(&lock);
}
void hdtext_reset(void) {
    pthread_mutex_lock(&lock);ready=0;font_slot=port_slot=window_slot=shape_finish=0;memset(shape_sites,0,sizeof(shape_sites));memset(font_offsets,0,sizeof(font_offsets));
    editor=heap_slot=0;y_capture=y_complete=y_extra_count=0;expression_active=-1;expression_next=0;memset(expressions,0,sizeof(expressions));
    memset(hdtext_pages,0,sizeof(hdtext_pages));memset(ports,0,sizeof(ports));memset(saves,0,sizeof(saves));next_save=0;
    pthread_mutex_unlock(&lock);
}
static int matches(Cell c,const uint8_t *pixels,int inverse) {
    int w=c.w,h=c.h,stride=c.font==0?6:h;
    if(w<1 || w>8 || h<1 || h>512 || c.font<0 || c.font>3)return 0;
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
/* Home and Y= share bottom borders and TEXT_EDIT geometry. Identify the
   visible toolbar before exporting either layout; cached pointers alone cannot
   identify the active application. Prgm remains enabled in Home history
   selection, where Algebra/Calc are deliberately shaded. */
static int home_toolbar_word(const uint8_t *pixels,int x,const char *word) {
    if(!font_offsets[0])return 0;
    for(;*word;word++) {
        Cell c=character(x,8,0,(unsigned char)*word,1);
        if(!matches(c,pixels,0))return 0;
        x+=c.w;
    }
    return 1;
}
static int editor_screen(const uint8_t *pixels) {
    if(!hdtext_active || !tihw.on_off || !pixels)return 0;
    for(int x=0;x<160;x++)if(!pixels[83*160+x] || !pixels[93*160+x])return 0;
    if(!home_toolbar_word(pixels,1,"Tools"))return 0;
    if(home_toolbar_word(pixels,88,"PrgmIO"))return 1;
    if(home_toolbar_word(pixels,21,"Zoom"))return 2;
    return 0;
}
int hdtext_copy_locked(const uint8_t *pixels,int32_t *out,int capacity) {
    int count=0;
    Port *p=port_for(tihw.lcd_adr,0);
    if(!p && tihw.lcd_adr==LCD_PORT)p=port_for(LCD_PORT,0);
    uint8_t clean[16000];int cursor_mask=0;
    if(hdtext_active && tihw.on_off && p && p->cursor_valid) {
        int home=editor_screen(pixels);
        if(home) {
            /* The medium ROM font has a blank final column. The cursor starts
               there, XORing it and the next character's first column. Read the
               actual rows already toggled, including snapshots mid-blink. */
            for(int y=0;y<8;y++)if(pixels[(85+y)*160+p->cursor_x])cursor_mask|=1<<y;
            if(cursor_mask) {
                memcpy(clean,pixels,sizeof clean);
                for(int y=0;y<8;y++)if(cursor_mask&(1<<y))for(int x=0;x<2;x++)clean[(85+y)*160+p->cursor_x+x]^=1;
                pixels=clean;
            }
        }
    }
    if(cursor_mask && capacity>0) {
        int32_t v[12]={p->cursor_x,85,4,0,cursor_mask,2,8,2,0,0,160,100};
        memcpy(out,v,sizeof v);count=1;
    }
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
    int screen=p ? editor_screen(pixels):0;

    if(screen) {
        /* Copy the complete editor, not its scrolled display slice. Resolve its
           movable heap handle afresh on every snapshot; never hold heap pointers. */
        int editor_complete=0;
        if(editor && heap_slot && editor+38<tihw.ram_size) {
            int flags=word_at(editor+32),n=word_at(editor+16),cur=word_at(editor+18),sel=word_at(editor+22),allocated=word_at(editor+14);
            uint32_t table=long_at(heap_slot),text=(flags&128)?long_at(editor+34):long_at(table+word_at(editor+34)*4);
            if(n>=0 && n<=512 && n<=allocated && cur<=n && text && text+(unsigned)n<tihw.ram_size && !(flags&1) && count+n+1<=capacity) {
                editor_complete=1;
                uint32_t parent=long_at(editor);
                int left=byte_at(parent+16)+(short)word_at(editor+6);
                int right=byte_at(parent+16)+(short)word_at(editor+10)+1;
                int32_t v[12]={cur,word_at(editor+20),8,flags,sel,n,screen-1,(int32_t)editor,left,84,right,93};memcpy(out+count++*12,v,sizeof v);
                for(int i=0;i<n;i++){int32_t ch[12]={i,0,9,byte_at(text+i),0,6,8,1,0,0,160,100};memcpy(out+count++*12,ch,sizeof ch);}
            }
        }
        /* An oversize live expression must keep the entire original body:
           drawing only its smaller neighbours would hide visible content. */
        int body_complete=editor_complete;
        for(int k=0;k<16;k++)if(expressions[k].complete<0) {
            Expression *e=&expressions[k];
            for(int j=0;j<e->count;j++)if(!e->items[j].kind) {
                Primitive q=e->items[j];Cell c={q.x-(q.font<2),q.y,q.font,q.code,q.attr,0,16,160,83,q.w,q.h,0};
                if(matches(c,pixels,0) || matches(c,pixels,1)){body_complete=0;break;}
            }
        }
        if(screen==2 && body_complete && count<capacity) {
            int32_t v[12]={0,16,10,0,0,160,67,0,0,16,160,83};memcpy(out+count++*12,v,sizeof v);
        }
        if(screen==2 && body_complete && y_complete)for(int i=0;i<y_extra_count && count<capacity;i++) {
            Cell c=y_extra[i];int32_t v[12]={c.x+(c.font<2),c.y,11,c.code,0,c.w,c.h,c.font,0,16,160,110};
            memcpy(out+count++*12,v,sizeof v);
        }
        for(int k=0;k<16 && body_complete;k++) {
            Expression *e=&expressions[k];if(e->complete!=1 || !e->count || count+e->count+1>capacity)continue;
            int inv=0,matched=0;
            for(int j=0;j<e->count;j++)if(e->items[j].kind==0) {
                Primitive q=e->items[j];Cell c={q.x-(q.font<2),q.y,q.font,q.code,q.attr,0,16,160,83,q.w,q.h,0};
                if(matches(c,pixels,0)){matched++;}else if(matches(c,pixels,1)){inv++;matched++;}
            }
            if(!matched && !(screen==2 && y_complete))continue; /* Completed Y= paint passes include deliberately clipped extra rows. */
            inv=inv*2>matched;
            int32_t header[12]={0,0,5,k,inv,e->count,0,0,0,16,160,83};memcpy(out+count++*12,header,sizeof header);
            for(int j=0;j<e->count;j++) {
                Primitive q=e->items[j];int32_t v[12]={q.x,q.y,q.kind?7:6,q.kind?q.x1:q.code,q.kind?q.y1:inv,q.kind?q.attr:q.w,q.h,q.font,k,16,160,83};
                memcpy(out+count++*12,v,sizeof v);
            }
        }
    }
    return count;
}
int hdtext_copy(const uint8_t *pixels,int32_t *out,int capacity) {
    pthread_mutex_lock(&lock);
    int count=hdtext_copy_locked(pixels,out,capacity);
    pthread_mutex_unlock(&lock);return count;
}
