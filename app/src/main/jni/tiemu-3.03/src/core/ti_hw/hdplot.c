/* True HD function plotting: extra evaluations through the verified AMS loop.
   No host expression parser and no interpolation of native raster curves. */
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <time.h>
#include "ti68k_def.h"
#include "libuae.h"
#include "hdplot.h"
#include "kbd.h"
#define MAX_POINTS 32768
#define MAX_DECORATIONS 16384
int hdplot_active;
unsigned char hdplot_pages[65536];
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;
static int enabled,factor=8,ready,supported,count,building,complete,overflow,loaded_cache;
static uint32_t evaluator,first_site,next_site,window_slot,win_clear,finish_site,finish_sp;
static uint8_t base[16000],reference[16000];
static float points[MAX_POINTS*2],bounds[4];
/* Axis drawing is observed only inside GrAxes and only on the actual LCD
   port. Window routines also draw to a backing port: never capture both. */
static uint32_t axes_call,line_call,pix_call,port_slot,axes_return,axes_sp;
static uint32_t bitmap_call,char_call,char_return,char_sp,graph_font_slot;
typedef struct {int x,y,valid;uint8_t pixels[48];} PromptGlyph;
static PromptGlyph prompt_glyphs[27];static int prompt_index,prompt_pending;
static uint32_t prompt_return,prompt_sp;
static int cursor_size=11;
static const unsigned cursor11[]={0x0400,0x0400,0x0e00,0x1500,0x2480,0xffe0,0x2480,0x1500,0x0e00,0x0400,0x0400};
static const unsigned cursor21[]={0x002000,0x002000,0x002000,0x00f800,0x032600,0x042100,0x082080,0x082080,0x102040,0x102040,0xfffff8,0x102040,0x102040,0x082080,0x082080,0x042100,0x032600,0x00f800,0x002000,0x002000,0x002000};
static int cursor_x,cursor_y,cursor_known,label_x,label_y,label_pending;
typedef struct {int x,y,code,valid,visible;uint8_t pixels[48];} PlotLabel;
static PlotLabel labels[4];static int label_index;
static int navigation_cursor,navigation_label;
static uint8_t trace_toolbar[480];static int trace_toolbar_valid,trace_mode,trace_requested;
static int trace_repeating;
static int previous_x,previous_y,previous_size;
int graph89_trace_repeat_factor=3;
static uint32_t hold_counter,hold_decrement[4];static int hold_sites;
static int graph_cursor_context,held_arrow=-1,hold_started_repeat;
static double held_since;
#ifdef GRAPH89_DRAW_TRACE
/* Isolated regressions can advance real-time input independently of CPU work. */
double graph89_cursor_test_time=-1;
#endif
static double cursor_time(void){
#ifdef GRAPH89_DRAW_TRACE
 if(graph89_cursor_test_time>=0)return graph89_cursor_test_time;
#endif
 struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;
}
static int decoration_count,decoration_bad,axes_capturing;
static float decorations[MAX_DECORATIONS*4];
static uint8_t decoration_mask[16000],before_axes[16000];
static double axis_x,axis_y,x_scale,y_scale,axis_xmin,axis_ymax,axis_dx,axis_dy;
static void decoration_pixel(int x,int y){if(x>=0&&x<159&&y>=16&&y<93)decoration_mask[y*160+x]=1;}
static void decoration_line(int x,int y,int u,int v){
 int dx=abs(u-x),sx=x<u?1:-1,dy=-abs(v-y),sy=y<v?1:-1,e=dx+dy;
 for(;;){decoration_pixel(x,y);if(x==u&&y==v)break;int e2=2*e;if(e2>=dy){e+=dy;x+=sx;}if(e2<=dx){e+=dx;y+=sy;}}
}
static double tick_x(int x){double world=axis_xmin+x*axis_dx;
 if(x_scale>0&&isfinite(x_scale)){double exact=round(world/x_scale)*x_scale;double mapped=(exact-axis_xmin)/axis_dx;if(fabs(mapped-x)<=0.51)return mapped+0.5;}
 return x+0.5;}
static double tick_y(int y){double world=axis_ymax-(y-16)*axis_dy;
 if(y_scale>0&&isfinite(y_scale)){double exact=round(world/y_scale)*y_scale;double mapped=16+(axis_ymax-exact)/axis_dy;if(fabs(mapped-y)<=0.51)return mapped+0.5;}
 return y+0.5;}
static void decoration(double x,double y,double u,double v){
 if(decoration_count>=MAX_DECORATIONS){decoration_bad=1;return;}
 float *d=decorations+decoration_count++*4;d[0]=x;d[1]=y;d[2]=u;d[3]=v;
}
static double xmin,xmax,ymin,ymax,last_x,current_x,step_x;
static int have_last,eval_active,extra_index,divisions;
static uint32_t eval_return,eval_sp,xptr,yptr,entry_regs[16];
static struct flag_struct entry_flags;
static uint8_t original_x[10];
static int byte_at(uint32_t a) {
 if(tihw.ram && a<tihw.ram_size)return tihw.ram[a];
 if(tihw.rom && a>=tihw.rom_base && a-tihw.rom_base<tihw.rom_size)return tihw.rom[a-tihw.rom_base];
 return -1;
}
static unsigned word_at(uint32_t a){int h=byte_at(a),l=byte_at(a+1);return h<0||l<0?0:(h<<8)|l;}
static uint32_t long_at(uint32_t a){return (word_at(a)<<16)|word_at(a+2);}
static uint32_t rom_call(unsigned id){uint32_t t=long_at(tihw.rom_base+0x12150);if(t<tihw.rom_base||t-tihw.rom_base>=tihw.rom_size||id>=long_at(t-4))return 0;return long_at(t+id*4);}
static void watch(uint32_t a){if(a)hdplot_pages[(a&0xffffff)>>8]=1;}
static double number_at(uint32_t a) {
 if(a+10>tihw.ram_size && !(a>=tihw.rom_base && a-tihw.rom_base+10<=tihw.rom_size))return NAN;
 unsigned e=word_at(a);if((e&0x7fff)>=0x7fff)return NAN;
 double v=0;for(int i=0;i<8;i++){int b=byte_at(a+2+i);if((b>>4)>9||(b&15)>9)return NAN;v=v*100+(b>>4)*10+(b&15);}
 return (e&0x8000?-1:1)*v*pow(10,(int)(e&0x7fff)-0x4000-15);
}
static int put_number(uint32_t a,double x) {
 if(a+10>tihw.ram_size||!isfinite(x))return 0;
 uint8_t b[10]={0};unsigned e=0x4000;if(x<0){e|=0x8000;x=-x;}
 if(x){int n=(int)floor(log10(x));double m=x/pow(10,n);if(!isfinite(m)||n < -1000||n>1000)return 0;e+=n;
  for(int i=0;i<16;i++){int d=(int)m;if(d>9)d=9;if(d<0)d=0;b[2+i/2]|=d<<(i%2?0:4);m=(m-d)*10;}}
 b[0]=e>>8;b[1]=e;memcpy(tihw.ram+a,b,10);return 1;
}
static void screen(uint8_t *out){for(int y=0;y<100;y++)for(int x=0;x<160;x++)out[y*160+x]=!!(tihw.ram[tihw.lcd_adr+y*30+x/8]&(0x80>>(x%8)));}
static void append(double x,double y,int valid) {
 if(count>=MAX_POINTS){overflow=1;return;}
 double px=bounds[0]+(x-xmin)/(xmax-xmin)*(bounds[2]-bounds[0]-1);
 double py=bounds[1]+(ymax-y)/(ymax-ymin)*(bounds[3]-bounds[1]-1);
 points[count*2]=valid && isfinite(px)&&isfinite(py)?(float)px:NAN;
 points[count*2+1]=valid && isfinite(px)&&isfinite(py)?(float)py:NAN;count++;
}
static void initialize(void) {
 if(ready||!tihw.rom)return;ready=1;
 if(tihw.calc_type!=TI89t || strcmp(tihw.rom_version,"3.10"))return;
 evaluator=rom_call(0x1d1);win_clear=rom_call(0xc);
 /* Exact caller fingerprints locate the same primary endpoint evaluations.
    Unknown AMS implementations are deliberately left untouched. */
 static const uint8_t first[]={0x70,0,0x2e,0x80,0x48,0x6e,0xff,0x54,0x3f,0x2e,0xfd,6,0x48,0x6e,0xfd,0x54,0x48,0x6e,0xfd,0x2c,0x3f,0x2e,0xfd,4,0x3f,0x2e,0xfd,2,0x2f,0x2e,0xfc,0xfe,0x4e,0xb9};
 static const uint8_t next[]={0x70,0,0x2e,0x80,0x48,0x6e,0xff,0x54,0x3f,0x2e,0xfd,6,0x48,0x6e,0xfd,0x5e,0x48,0x6e,0xfd,0x36,0x3f,0x2e,0xfd,4,0x3f,0x2e,0xfd,2,0x2f,0x2e,0xfc,0xfe,0x4e,0xb9};
 int nf=0,nn=0;
 for(uint32_t pos=0;pos+64<tihw.rom_size;pos+=2){uint32_t a=tihw.rom_base+pos;
  if(long_at(a+34)!=evaluator||long_at(a+38)!=0x4fef0018)continue;
  if(!memcmp(tihw.rom+pos,first,sizeof first)){first_site=a+38;nf++;}
  if(!memcmp(tihw.rom+pos,next,sizeof next)){next_site=a+38;nn++;}}
 if(nf!=1||nn!=1||next_site-first_site!=242)return;
 /* The first post-evaluation y conversion reads the live GR_WIN_VARS global. */
 if(word_at(first_site+8)!=0x2eb9)return;window_slot=long_at(first_site+10);
 if(window_slot+4>tihw.ram_size||word_at(evaluator)!=0x4e56||word_at(evaluator+2)!=0xfff8)return;
 /* Derive the live first-repeat countdown from the verified OSInitKeyDelay
    load/store, then verify its interrupt decrement sites. No fixed RAM address. */
 uint32_t delay=rom_call(0x248),initial=0;
 if(word_at(delay)==0x7200 && word_at(delay+2)==0x322f && word_at(delay+4)==4 && word_at(delay+6)==0x3039 && word_at(delay+12)==0x33c1 && long_at(delay+8)==long_at(delay+14) && word_at(delay+18)==0x4e75)initial=long_at(delay+8);
 if(initial && initial+2<tihw.ram_size){
  for(uint32_t q=tihw.rom_base;q+10<tihw.rom_base+tihw.rom_size;q+=2)
   if(word_at(q)==0x33f9 && long_at(q+2)==initial){uint32_t counter=long_at(q+6);if(counter+2<tihw.ram_size){hold_counter=counter;break;}}
  for(uint32_t q=tihw.rom_base;hold_counter && q+6<tihw.rom_base+tihw.rom_size;q+=2)
   if(word_at(q)==0x5379 && long_at(q+2)==hold_counter){if(hold_sites<4){hold_decrement[hold_sites++]=q;watch(q);}else{hold_counter=0;break;}}
 }
 supported=1;watch(evaluator);watch(win_clear);watch(first_site);watch(next_site);
 uint32_t port_restore=rom_call(0x1a3);
 if(word_at(port_restore)==0x23fc && long_at(port_restore+2)==0x4c00){
  port_slot=long_at(port_restore+6);
  if(port_slot+4<tihw.ram_size){axes_call=rom_call(0x1b7);line_call=rom_call(0x1a7);pix_call=rom_call(0x1a8);watch(axes_call);watch(line_call);watch(pix_call);uint32_t getter=rom_call(0x18e);if(word_at(getter)==0x1039 && word_at(getter+6)==0x4e75)graph_font_slot=long_at(getter+2);bitmap_call=rom_call(0x187);char_call=rom_call(0x1a4);watch(bitmap_call);watch(char_call);}
 }
}
void hdplot_observe(uint32_t pc) {
 uint32_t sp=m68k_areg(regs,7),a=sp+4;
 if(hold_counter && graph_cursor_context && held_arrow>=0 && !hold_started_repeat && tihw.on_off && trace_toolbar_valid && !memcmp(trace_toolbar,tihw.ram+tihw.lcd_adr,480)){
  for(int k=0;k<hold_sites;k++)if(pc==hold_decrement[k]){
   int delay=cursor_time()-held_since<0.5?2:1;
   tihw.ram[hold_counter]=0;tihw.ram[hold_counter+1]=delay;
   if(delay==1)hold_started_repeat=1;
  }
 }
 if(eval_active && pc==eval_return && sp==eval_sp+4) {
  if(enabled && building)append(number_at(xptr),number_at(yptr),(m68k_dreg(regs,0)&65535)==1);
  if(extra_index>0){extra_index=enabled?extra_index-1:0;memcpy(regs.regs,entry_regs,sizeof entry_regs);regs.flags=entry_flags;
   if(!extra_index || !put_number(xptr,current_x-step_x*extra_index/divisions)){extra_index=0;memcpy(tihw.ram+xptr,original_x,10);}
   m68k_setpc(evaluator);fill_prefetch_slow();return;}
  have_last=1;last_x=current_x;eval_active=0;hdplot_active=1;
 }
 /* Graph Math prompts are medium-font DrawChar cells above the readouts.
    Retain full cells rather than just pixels that differ from the graph. */
 if(prompt_pending && pc==prompt_return && sp==prompt_sp+4){
  PromptGlyph *g=&prompt_glyphs[prompt_index];uint8_t lcd[16000];screen(lcd);
  for(int y=0;y<8;y++)for(int x=0;x<6;x++)g->pixels[y*6+x]=lcd[(g->y+y)*160+g->x+x];
  g->valid=1;prompt_pending=0;
 }
 if(pc==char_call && long_at(port_slot)==tihw.lcd_adr && graph_font_slot && byte_at(graph_font_slot)==1){
  int x=(short)word_at(a)+1,y=(short)word_at(a+2),code=word_at(a+4);
  if(code>32 && code<127 && x>=0 && x+6<=159 && y>=74 && y+8<=85){
   prompt_index=0;while(prompt_index<26 && prompt_glyphs[prompt_index].valid && (prompt_glyphs[prompt_index].x!=x || prompt_glyphs[prompt_index].y!=y))prompt_index++;
   prompt_glyphs[prompt_index].x=x;prompt_glyphs[prompt_index].y=y;prompt_glyphs[prompt_index].valid=0;
   prompt_pending=1;prompt_return=long_at(sp);prompt_sp=sp;watch(prompt_return);
  }
 }
 if(label_pending && pc==char_return && sp==char_sp+4){
  uint8_t lcd[16000];screen(lcd);for(int y=0;y<8;y++)for(int x=0;x<6;x++)labels[label_index].pixels[y*6+x]=lcd[(label_y+y)*160+label_x+x];labels[label_index].valid=1;memcpy(trace_toolbar,tihw.ram+tihw.lcd_adr,480);trace_toolbar_valid=1;if(trace_requested)trace_mode=1;label_pending=0;
 }
 if(pc==char_call && long_at(port_slot)==tihw.lcd_adr){
  int x=(short)word_at(a)+1,y=(short)word_at(a+2),code=word_at(a+4);
  if(graph_font_slot && byte_at(graph_font_slot)==1 && x>=140 && x+6<=159 && y>=16 && y+8<=29 && code>=48 && code<=57){label_index=0;while(label_index<3 && labels[label_index].valid && (labels[label_index].x!=x || labels[label_index].y!=y))label_index++;labels[label_index].x=x;labels[label_index].y=y;labels[label_index].code=code;labels[label_index].valid=0;label_x=x;label_y=y;label_pending=1;char_return=long_at(sp);char_sp=sp;watch(char_return);}
 }
 if(pc==bitmap_call && long_at(port_slot)==tihw.lcd_adr && (word_at(a+12)==1 || word_at(a+12)==2)){
  uint32_t b=long_at(a+4);int size=word_at(b),stride=size==21?3:2;
  const unsigned *rows=size==21?cursor21:cursor11;
  int matches=(size==11 || size==21) && word_at(b+2)==size;
  for(int y=0;y<size&&matches;y++){unsigned row=0;for(int x=0;x<stride;x++)row=(row<<8)|byte_at(b+4+y*stride+x);matches=row==rows[y];}
  if(matches){graph_cursor_context=1;memcpy(trace_toolbar,tihw.ram+tihw.lcd_adr,480);trace_toolbar_valid=1;if(cursor_known){previous_x=cursor_x;previous_y=cursor_y;previous_size=cursor_size;}if(size==21 && trace_mode)trace_repeating=1;cursor_x=(short)word_at(a);cursor_y=(short)word_at(a+2);cursor_size=size;cursor_known=1;}
 }
 if(!enabled)return;

 if(pc==finish_site && sp==finish_sp && building){screen(reference);building=0;complete=!overflow&&!eval_active;eval_active=0;finish_site=0;}
 if(axes_capturing && pc==axes_return && sp==axes_sp+4){
  axes_capturing=0;axes_return=0;
  /* An empty graph has no function-evaluator calls. Publish its completed
     axes immediately; the first curve call replaces this provisional cache. */
  if(!building&&!decoration_bad){screen(reference);memcpy(base,reference,sizeof base);
   for(int i=0;i<16000;i++)if(decoration_mask[i])base[i]=before_axes[i];
   bounds[0]=0;bounds[1]=16;bounds[2]=159;bounds[3]=93;
   count=3;for(int i=0;i<6;i++)points[i]=NAN;complete=1;overflow=0;
  }
 }
 if(pc==axes_call && !building){
  uint32_t gv=long_at(a+2),win=gv+0x246<tihw.ram_size?long_at(gv+0x242):0;
  uint32_t range=gv+164<tihw.ram_size?long_at(gv+160):0;
  if(gv==long_at(window_slot)&&gv+0x31a<tihw.ram_size&&byte_at(gv+0x319)==1&&win+28<tihw.ram_size&&range+60<tihw.ram_size&&byte_at(win+16)==0&&byte_at(win+17)==16&&byte_at(win+18)==158&&byte_at(win+19)==92){
   decoration_count=decoration_bad=0;memset(decoration_mask,0,sizeof decoration_mask);screen(before_axes);
   axis_xmin=number_at(range);axis_ymax=number_at(range+40);
   axis_dx=(number_at(range+10)-axis_xmin)/158;axis_dy=(axis_ymax-number_at(range+30))/76;
   x_scale=number_at(range+20);y_scale=number_at(range+50);
   axis_x=-axis_xmin/axis_dx;axis_y=16+axis_ymax/axis_dy;
   xmin=axis_xmin;xmax=number_at(range+10);ymin=number_at(range+30);ymax=axis_ymax;
   if(isfinite(axis_x)&&isfinite(axis_y)&&axis_dx>0&&axis_dy>0){axes_capturing=1;axes_return=long_at(sp);axes_sp=sp;watch(axes_return);}
  }
 }
 if(axes_capturing && (pc==line_call||pc==pix_call) && long_at(port_slot)==tihw.lcd_adr){
  int x=(short)word_at(a),y=(short)word_at(a+2);
  int u=pc==line_call?(short)word_at(a+4):x,v=pc==line_call?(short)word_at(a+6):y;
  int attr=word_at(a+(pc==line_call?8:4));
  if(attr!=1||x<0||u<0||x>158||u>158||y<16||v<16||y>92||v>92){decoration_bad=1;}
  else {
   decoration_line(x,y,u,v);
   if(pc==line_call){
    double xx=x+0.5,yy=y+0.5,uu=u+0.5,vv=v+0.5;
    if(x==u && abs(v-y)>3 && fabs(x-axis_x)<=0.51)xx=uu=axis_x+0.5;
    if(y==v && abs(u-x)>3 && fabs(y-axis_y)<=0.51)yy=vv=axis_y+0.5;
    decoration(xx,yy,uu,vv);
   }else if(fabs(x-(round(axis_x)+1))<0.1){double ty=tick_y(y);decoration(axis_x+0.5,ty,axis_x+1.5,ty);}
   else if(fabs(y-(round(axis_y)-1))<0.1){double tx=tick_x(x);decoration(tx,axis_y-0.5,tx,axis_y+0.5);}
   else {double tx=tick_x(x),ty=tick_y(y);decoration(tx,ty,tx,ty);}
  }
 }
 if(pc==win_clear && building==0){uint32_t gv=long_at(window_slot);if(gv+0x246<tihw.ram_size && long_at(a)==long_at(gv+0x242)){count=0;complete=0;have_last=0;overflow=0;decoration_count=decoration_bad=axes_capturing=0;memset(decoration_mask,0,sizeof decoration_mask);}}
 if(pc!=evaluator||eval_active)return;
 uint32_t caller=long_at(sp),gv=long_at(window_slot);
 if(caller!=first_site && caller!=next_site)return;
 /* Only ordinary, full-screen y=f(x) plots are supported in this prototype. */
 if(!supported||gv+0x31a>=tihw.ram_size||byte_at(gv+0x319)!=1)return;
 uint32_t win=long_at(gv+0x242),range=long_at(gv+160);
 if(win+28>=tihw.ram_size||range+50>=tihw.ram_size||byte_at(win+16)!=0||byte_at(win+17)!=16||byte_at(win+18)!=158||byte_at(win+19)!=92)return;
 xptr=long_at(a+8);yptr=long_at(a+12);if(xptr+10>=tihw.ram_size||yptr+10>=tihw.ram_size)return;
 if(caller==first_site){
  have_last=0;
  if(!building){
   uint8_t current[16000];screen(current);
   double nxmin=number_at(range),nxmax=number_at(range+10),nymin=number_at(range+30),nymax=number_at(range+40);
   /* AMS can add a selected function without clearing/replotting previous
      ones. Keep their vectors and clean background only if this is exactly
      the previously captured graph in the same mathematical window. */
   int extend=complete&&!overflow&&count>3&&xmin==nxmin&&xmax==nxmax&&ymin==nymin&&ymax==nymax&&!memcmp(current,reference,93*160);
   if(!extend){count=0;memcpy(base,current,sizeof base);
    if(!decoration_bad){for(int i=0;i<16000;i++)if(decoration_mask[i])base[i]=before_axes[i];}else decoration_count=0;
   }
   overflow=0;complete=0;building=1;memcpy(reference,current,sizeof reference);
   xmin=number_at(range);xmax=number_at(range+10);ymin=number_at(range+30);ymax=number_at(range+40);
   bounds[0]=0;bounds[1]=16;bounds[2]=159;bounds[3]=93;
   uint32_t frame=m68k_areg(regs,6);finish_site=long_at(frame+4);finish_sp=frame+8;watch(finish_site);
  }
  /* The verified caller stores its graph style in this local byte. Only
     the default connected-line style is supported; preserve other styles. */
  if(byte_at(m68k_areg(regs,6)-0x174)!=0){overflow=1;return;}
  append(NAN,NAN,0);
 }
 if(!building||!isfinite(xmin)||!isfinite(xmax)||!isfinite(ymin)||!isfinite(ymax)||xmin>=xmax||ymin>=ymax||!isfinite(xmax-xmin)||!isfinite(ymax-ymin))return;
 current_x=number_at(xptr);step_x=current_x-last_x;
 if(!isfinite(current_x))return;
 eval_return=caller;eval_sp=sp;
 /* xres may skip multiple native columns. Keep the same HD density rather
    than merely subdividing every coarse native interval eight times. */
 double intervals=step_x/(xmax-xmin)*158*factor;
 divisions=have_last && isfinite(intervals) && intervals>0 && intervals<=160 ? (int)ceil(intervals-1e-7):1;
 if(divisions<1)divisions=1;
 extra_index=!overflow?divisions-1:0;
 memcpy(original_x,tihw.ram+xptr,10);memcpy(entry_regs,regs.regs,sizeof entry_regs);entry_flags=regs.flags;eval_active=1;
 if(extra_index && !put_number(xptr,current_x-step_x*extra_index/divisions))extra_index=0;
}
/* Both graph cursors use the same budget, only after a real-time half-second
   hold. Native keyboard processing still owns each movement and key release. */
void hdplot_cursor_speed(int multiplier){pthread_mutex_lock(&lock);graph89_trace_repeat_factor=multiplier<1?1:multiplier>10?10:multiplier;pthread_mutex_unlock(&lock);}
void hdplot_key_event(int key,int pressed){
 int arrow=key==TIKEY_LEFT || key==TIKEY_RIGHT || key==TIKEY_UP || key==TIKEY_DOWN;
 if(!arrow && pressed){graph_cursor_context=0;trace_mode=0;trace_requested=key==TIKEY_F3 && !ti68k_kbd_is_key_pressed(TIKEY_DIAMOND) && !ti68k_kbd_is_key_pressed(TIKEY_2ND) && !ti68k_kbd_is_key_pressed(TIKEY_SHIFT);}
 if(arrow && pressed && held_arrow!=key){held_arrow=key;held_since=cursor_time();hold_started_repeat=0;}
 if((arrow && !pressed && held_arrow==key) || (!arrow && pressed)){held_arrow=-1;hold_started_repeat=0;}
 if(!arrow || !pressed)trace_repeating=0;
}
int hdplot_trace_multiplier(void){
 if(!graph_cursor_context || held_arrow<0 || cursor_time()-held_since<0.5 || !tihw.on_off || !trace_toolbar_valid || memcmp(trace_toolbar,tihw.ram+tihw.lcd_adr,480))return 1;
 if(!ti68k_kbd_is_key_pressed(held_arrow))return 1;
 uint32_t gv=long_at(window_slot),win=gv+0x246<tihw.ram_size?long_at(gv+0x242):0;
 if(gv+0x31a>=tihw.ram_size || byte_at(gv+0x319)!=1 || win+28>=tihw.ram_size || byte_at(win+16)!=0 || byte_at(win+17)!=16 || byte_at(win+18)!=158 || byte_at(win+19)!=92)return 1;
 return graph89_trace_repeat_factor;
}
void hdplot_run_begin(void){pthread_mutex_lock(&lock);initialize();}
void hdplot_run_end(void){
 /* Live frames validate only the unchanged toolbar in base. The exact LCD
    reference is captured at plot completion (or the empty-graph axes return),
    so recopying 16,000 pixels after every CPU batch serves no consumer. */
 pthread_mutex_unlock(&lock);
}

void hdplot_enable(int on,int samples){pthread_mutex_lock(&lock);
 samples=samples<2?2:samples>16?16:samples;
 /* Complete a pending synthetic call before changing its factor or disabling. */
 if(!eval_active)factor=samples;
 if(enabled!=(on!=0)){enabled=on!=0;if(!(enabled&&loaded_cache)){complete=0;if(!eval_active){count=0;building=0;have_last=0;}}loaded_cache=0;}
 hdplot_active=1;pthread_mutex_unlock(&lock);}
void hdplot_reset(void){pthread_mutex_lock(&lock);ready=supported=count=building=complete=overflow=have_last=eval_active=loaded_cache=0;cursor_known=label_pending=navigation_cursor=navigation_label=0;memset(labels,0,sizeof labels);memset(prompt_glyphs,0,sizeof prompt_glyphs);prompt_pending=0;trace_toolbar_valid=trace_mode=trace_requested=trace_repeating=previous_size=0;graph_cursor_context=hold_sites=hold_counter=hold_started_repeat=0;held_arrow=-1;finish_site=0;axes_capturing=decoration_count=decoration_bad=0;axes_return=port_slot=axes_call=line_call=pix_call=0;memset(decoration_mask,0,sizeof decoration_mask);memset(hdplot_pages,0,sizeof hdplot_pages);hdplot_active=1;pthread_mutex_unlock(&lock);}
/* Keep calculator-owned cursors, coordinate readouts and popup menus above
   the cached vector scene. Bit 1 in the background marks native overlay pixels;
   renderers exclude these patches so the current LCD/text underneath remains
   visible. The mathematical window and several complete graph toolbar tiles
   must still identify the same graph; a saved curve never covers Home or Y=. */
static int same_window(void){
 uint32_t gv=long_at(window_slot),win=gv+0x246<tihw.ram_size?long_at(gv+0x242):0;
 uint32_t range=gv+164<tihw.ram_size?long_at(gv+160):0;
 return gv+0x31a<tihw.ram_size && byte_at(gv+0x319)==1 && win+28<tihw.ram_size && range+60<tihw.ram_size
  && byte_at(win+16)==0 && byte_at(win+17)==16 && byte_at(win+18)==158 && byte_at(win+19)==92
  && number_at(range)==xmin && number_at(range+10)==xmax && number_at(range+30)==ymin && number_at(range+40)==ymax;
}
static void overlay_patch(const uint8_t *pixels,uint8_t *background,int l,int t,int r,int b){
 int left=r,top=b,right=l,bottom=t;
 for(int y=t;y<b;y++)for(int x=l;x<r;x++)if(pixels[y*160+x]!=reference[y*160+x]){
  if(x<left)left=x;if(x>=right)right=x+1;if(y<top)top=y;if(y>=bottom)bottom=y+1;
 }
 /* Include unchanged pixels inside the patch: popup whitespace must conceal
    the curve too, and a cursor must not leave the old raster curve beneath it. */
 for(int y=top;y<bottom;y++)for(int x=left;x<right;x++)background[y*160+x]|=2;
}
static int navigation_background(const uint8_t *pixels,uint8_t *background){
 navigation_cursor=navigation_label=0;
 if(!same_window())return 0;
 static const int edges[]={0,20,41,62,93,112,132,146};int tiles=0;
 for(int tile=0;tile<7;tile++){
  int same=1;for(int y=0;y<16 && same;y++)for(int x=edges[tile];x<edges[tile+1];x++)
   if(pixels[y*160+x]!=reference[y*160+x]){same=0;break;}
  tiles+=same;
 }
 if(tiles<4)return 0;
 memcpy(background,base,16000);
 /* Coordinate fields and Trace's function number are separate overlays. They
    must not enlarge the cursor/popup patch across the otherwise unchanged plot. */
 overlay_patch(pixels,background,0,83,80,93);
 overlay_patch(pixels,background,80,83,159,93);
 overlay_patch(pixels,background,140,16,159,29);
 int left=159,top=83,right=0,bottom=16;
 for(int y=16;y<83;y++)for(int x=0;x<159;x++){
  if(x>=140 && y<29)continue;
  if(pixels[y*160+x]==reference[y*160+x])continue;
  if(x<left)left=x;if(x>=right)right=x+1;if(y<top)top=y;if(y>=bottom)bottom=y+1;
 }
 if(tiles==7 && (right-left>13 || bottom-top>13)) {
  /* Drawing annotations are retained as their changed native pixels instead
     of replacing a large rectangular part of the HD graph. Popup menus have
     a selected toolbar tile and need their complete opaque rectangle. */
  for(int y=16;y<83;y++)for(int x=0;x<159;x++)if(pixels[y*160+x]!=reference[y*160+x])background[y*160+x]|=2;
 }else {
  int mask=right-left<=13 && bottom-top<=13?6:2; /* bit 2 protects a small native cursor from text matching */
  for(int y=top;y<bottom;y++)for(int x=left;x<right;x++)background[y*160+x]|=mask;
 }
 /* Validate both blink phases against the known bitmap, rather than
    inferring its centre from ink that can cancel against a curve. */
 if(cursor_known && cursor_x+cursor_size>0 && cursor_x<159 && cursor_y+cursor_size>16 && cursor_y<83){
  const unsigned *rows=cursor_size==21?cursor21:cursor11;int stride=cursor_size==21?24:16,same=1,blank=1;
  for(int y=0;y<cursor_size;y++)for(int x=0;x<cursor_size;x++){int px=cursor_x+x,py=cursor_y+y;if(px<0||px>=159||py<16||py>=83)continue;int i=py*160+px,ink=(rows[y]&(1u<<(stride-1-x)))!=0;
   if(pixels[i]!=(cursor_size==21?(reference[i]^ink):(ink?1:reference[i])))same=0;
   if(pixels[i]!=(cursor_size==21?reference[i]:(ink?0:reference[i])))blank=0;
  }
  int transition=0;
  if(!same && !blank && graph_cursor_context && (ti68k_kbd_is_key_pressed(TIKEY_LEFT)||ti68k_kbd_is_key_pressed(TIKEY_RIGHT)||ti68k_kbd_is_key_pressed(TIKEY_UP)||ti68k_kbd_is_key_pressed(TIKEY_DOWN))){
   transition=1;for(int y=16;y<83 && transition;y++)for(int x=0;x<159;x++){
    if(x>=140 && y<29)continue;if(pixels[y*160+x]==reference[y*160+x])continue;
    if(!(x>=cursor_x && x<cursor_x+cursor_size && y>=cursor_y && y<cursor_y+cursor_size) && !(previous_size && x>=previous_x && x<previous_x+previous_size && y>=previous_y && y<previous_y+previous_size)){transition=0;break;}
   }
  }
  if(transition){same=1;for(int y=0;y<previous_size;y++)for(int x=0;x<previous_size;x++){int px=previous_x+x,py=previous_y+y;if(px>=0&&px<159&&py>=16&&py<83)background[py*160+px]=(background[py*160+px]&1)|4;}}
  if(same||blank){navigation_cursor=(cursor_size==21?2:0)+(same?1:2);for(int y=0;y<cursor_size;y++)for(int x=0;x<cursor_size;x++){int px=cursor_x+x,py=cursor_y+y;if(px>=0&&px<159&&py>=16&&py<83)background[py*160+px]=(background[py*160+px]&1)|4;}}
 }
 for(int k=0;k<4;k++){PlotLabel *label=&labels[k];label->visible=0;if(!label->valid)continue;
  int same=1;for(int y=0;y<8;y++)for(int x=0;x<6;x++)if(pixels[(label->y+y)*160+label->x+x]!=label->pixels[y*6+x])same=0;
  if(same){navigation_label=1;label->visible=1;for(int y=0;y<8;y++)for(int x=0;x<6;x++)background[(label->y+y)*160+label->x+x]|=2;}
 }
 int prompt_left=159,prompt_right=0,prompt_top=85,prompt_bottom=0;
 for(int k=0;k<27;k++){PromptGlyph *g=&prompt_glyphs[k];if(!g->valid)continue;
  int same=1;for(int y=0;y<8 && same;y++)for(int x=0;x<6;x++)if(pixels[(g->y+y)*160+g->x+x]!=g->pixels[y*6+x]){same=0;break;}
  if(same){if(g->x<prompt_left)prompt_left=g->x;if(g->x+6>prompt_right)prompt_right=g->x+6;if(g->y<prompt_top)prompt_top=g->y;if(g->y+8>prompt_bottom)prompt_bottom=g->y+8;}
 }
 for(int y=prompt_top;y<prompt_bottom;y++)for(int x=prompt_left;x<prompt_right;x++){int i=y*160+x;background[i]=(background[i]&1)|2;}
 return 1;
}
int hdplot_copy(const uint8_t *pixels,float *out,int capacity,uint8_t *background){pthread_mutex_lock(&lock);int n=0;navigation_cursor=navigation_label=0;
 int live=building&&!overflow&&(tihw.ram[tihw.lcd_adr+99*30+19]&1);
 int exported=count<3?3:count;
 if(enabled&&(complete||live)&&tihw.on_off&&count>0&&capacity>=exported*2+4){int valid=1;
  /* Active plotting still validates its stable toolbar. Completed scenes
     accept calculator-owned interaction overlays in the same graph window. */
  if(live){for(int y=0;y<16 &&valid;y++)for(int x=0;x<160;x++)if(pixels[y*160+x]!=base[y*160+x]){valid=0;break;}
   if(valid)memcpy(background,base,16000);
  }else valid=navigation_background(pixels,background);
  if(valid){memcpy(out,bounds,sizeof bounds);memcpy(out+4,points,count*2*sizeof(float));
   for(int i=count*2;i<exported*2;i++)out[i+4]=NAN;
   n=exported*2+4;}}
 pthread_mutex_unlock(&lock);return n;}

int hdplot_copy_decorations(float *out,int capacity){pthread_mutex_lock(&lock);
 int n=enabled&&(complete||(building&&!overflow&&(tihw.ram[tihw.lcd_adr+99*30+19]&1)))&&!decoration_bad&&capacity>=decoration_count*4?decoration_count*4:0;
 if(n)memcpy(out,decorations,n*sizeof(float));
 if(navigation_cursor && capacity>=n+4){out[n++]=NAN;out[n++]=-navigation_cursor;out[n++]=cursor_x+cursor_size/2.0f;out[n++]=cursor_y+cursor_size/2.0f;}
 if(navigation_label)for(int k=0;k<4;k++)if(labels[k].visible && capacity>=n+4){out[n++]=NAN;out[n++]=labels[k].code;out[n++]=labels[k].x;out[n++]=labels[k].y;}
 pthread_mutex_unlock(&lock);return n;}

/* A saved state may land inside an additional ROM evaluation. Retain only
   the continuation needed to finish that call and restore its original sample.
   Completed vector caches also survive loading, validated against the original
   LCD before display. Old states have no trailer; older apps ignore trailing
   bytes. All fields have fixed byte order. */
static void write32(FILE *f,uint32_t v){uint8_t b[4]={v>>24,v>>16,v>>8,v};fwrite(b,1,4,f);}
static int read32(FILE *f,uint32_t *v){uint8_t b[4];if(fread(b,1,4,f)!=4)return 0;*v=((uint32_t)b[0]<<24)|((uint32_t)b[1]<<16)|(b[2]<<8)|b[3];return 1;}
void hdplot_save_pending(FILE *f){pthread_mutex_lock(&lock);fwrite("G89HDP01",1,8,f);
 uint32_t v[30]={1,eval_active,evaluator,eval_return,eval_sp,xptr,yptr,factor,extra_index>0};
 memcpy(v+9,entry_regs,16*sizeof(uint32_t));v[25]=entry_flags.c;v[26]=entry_flags.z;v[27]=entry_flags.n;v[28]=entry_flags.v;v[29]=entry_flags.x;
 for(int i=0;i<30;i++)write32(f,v[i]);fwrite(original_x,1,10,f);
 fwrite("G89PLOT1",1,8,f);int cached=complete&&!building&&!eval_active&&!overflow;
 write32(f,cached?count:0);
 if(cached){for(int i=0;i<4+count*2;i++){uint32_t bits;float value=i<4?bounds[i]:points[i-4];memcpy(&bits,&value,4);write32(f,bits);}fwrite(base,1,16000,f);fwrite(reference,1,16000,f);}
 fwrite("G89AXES1",1,8,f);write32(f,cached?decoration_count:0);
 if(cached)for(int i=0;i<decoration_count*4;i++){uint32_t bits;memcpy(&bits,decorations+i,4);write32(f,bits);}
 pthread_mutex_unlock(&lock);}
void hdplot_load_pending(FILE *f){hdplot_reset();pthread_mutex_lock(&lock);char magic[8];uint32_t v[30];uint8_t x[10];
 if(fread(magic,1,8,f)!=8||memcmp(magic,"G89HDP01",8))goto done;
 for(int i=0;i<30;i++)if(!read32(f,v+i))goto done;
 if(fread(x,1,10,f)!=10||v[0]!=1)goto done;
 initialize();
 if(v[1]==0)goto cache;
 if(v[1]!=1)goto done;
 if(!supported||v[2]!=evaluator||(v[3]!=first_site&&v[3]!=next_site)||v[4]+28>=tihw.ram_size||v[5]+10>=tihw.ram_size||v[6]+10>=tihw.ram_size||v[7]<2||v[7]>16||v[8]>1||v[24]!=v[4]||long_at(v[4])!=v[3]||long_at(v[4]+12)!=v[5]||long_at(v[4]+16)!=v[6])goto done;
 eval_return=v[3];eval_sp=v[4];xptr=v[5];yptr=v[6];factor=v[7];extra_index=v[8];memcpy(entry_regs,v+9,sizeof entry_regs);memcpy(original_x,x,10);
 entry_flags=(struct flag_struct){v[25],v[26],v[27],v[28],v[29]};eval_active=1;hdplot_active=1;goto done;
 cache:
 if(!supported||fread(magic,1,8,f)!=8||memcmp(magic,"G89PLOT1",8))goto done;
 uint32_t n;if(!read32(f,&n)||n<3||n>MAX_POINTS)goto done;
 for(uint32_t i=0;i<4+n*2;i++){uint32_t bits;float value;if(!read32(f,&bits))goto done;memcpy(&value,&bits,4);if(i<4)bounds[i]=value;else points[i-4]=value;}
 if(bounds[0]!=0||bounds[1]!=16||bounds[2]!=159||bounds[3]!=93)goto done;
 if(fread(base,1,16000,f)!=16000||fread(reference,1,16000,f)!=16000)goto done;
 for(int i=0;i<16000;i++)if(base[i]>1||reference[i]>1)goto done;
 count=n;complete=loaded_cache=1;
 /* Window values are part of the loaded calculator RAM. Restore their
    metadata too, so adding a function after reopening keeps prior vectors. */
 uint32_t gv=long_at(window_slot),range=gv+164<tihw.ram_size?long_at(gv+160):0;
 if(range+50<tihw.ram_size){xmin=number_at(range);xmax=number_at(range+10);ymin=number_at(range+30);ymax=number_at(range+40);}
 /* Old caches keep their original axes bitmap. A malformed new vector
    trailer cannot leave the cleaned background without its decorations. */
 size_t trailer=fread(magic,1,8,f);
 if(trailer && (trailer!=8||memcmp(magic,"G89AXES1",8))){complete=loaded_cache=0;goto done;}
 if(trailer==8){
  uint32_t nd;if(!read32(f,&nd)||nd>MAX_DECORATIONS){complete=loaded_cache=0;goto done;}
  for(uint32_t i=0;i<nd*4;i++){uint32_t bits;float value;if(!read32(f,&bits)){complete=loaded_cache=0;goto done;}memcpy(&value,&bits,4);
   if(!isfinite(value)||value<0||value>159){complete=loaded_cache=0;goto done;}decorations[i]=value;}
  decoration_count=nd;
 }
 done:pthread_mutex_unlock(&lock);}

int hdplot_pending(void){pthread_mutex_lock(&lock);int value=eval_active?(extra_index?2:1):0;pthread_mutex_unlock(&lock);return value;}
