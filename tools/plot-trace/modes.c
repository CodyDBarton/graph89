/* Isolated six-mode HD and held-arrow regressions; never uses an app session. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <sys/stat.h>
#include "Graph89Core.h"
#include "ti68k_def.h"
#include "libuae.h"
#include "keydefs.h"
#include "romcalls.h"
#include "hdplot.h"
extern double graph89_cursor_test_time;
static uint32_t gr_slot,heap_slot;
static unsigned word(uint32_t a){return a+2<=tihw.ram_size?(tihw.ram[a]<<8)|tihw.ram[a+1]:0;}
static uint32_t lng(uint32_t a){return (word(a)<<16)|word(a+2);}
static double number(uint32_t a){if(a+10>tihw.ram_size)return NAN;unsigned e=word(a);if((e&0x7fff)>=0x7fff)return NAN;double v=0;for(int i=0;i<8;i++){int b=tihw.ram[a+2+i];if((b>>4)>9||(b&15)>9)return NAN;v=v*100+(b>>4)*10+(b&15);}return (e&0x8000?-1:1)*v*pow(10,(int)(e&0x7fff)-0x4000-15);}
static void run(int n){graph89_run(n);}
static void tap(int k){graph89_key(k,1);run(400000);graph89_key(k,0);run(400000);}
static void text(const char *s){graph89_type_text(s);run(30000000+(int)strlen(s)*400000);}
static void snapshot(const char *dir,const char *name){
 char path[4096];uint8_t lcd[16000],bg[16000];float pts[65540],decs[65536];graph89_copy_screen(lcd);int n=graph89_copy_hd_plot(lcd,pts,65540,bg),nd=n?graph89_copy_hd_plot_decorations(decs,65536):0;
 snprintf(path,sizeof path,"%s/%s.pgm",dir,name);FILE *f=fopen(path,"wb");fprintf(f,"P5\n160 100\n255\n");fwrite(lcd,1,16000,f);fclose(f);
 snprintf(path,sizeof path,"%s/%s.points",dir,name);f=fopen(path,"w");for(int i=0;i<n;i+=2)fprintf(f,"%.9g %.9g\n",pts[i],pts[i+1]);fclose(f);
 snprintf(path,sizeof path,"%s/%s.geometry",dir,name);f=fopen(path,"w");for(int i=0;i<nd;i+=4)fprintf(f,"%.9g %.9g %.9g %.9g\n",decs[i],decs[i+1],decs[i+2],decs[i+3]);fclose(f);
 snprintf(path,sizeof path,"%s/%s.background.pgm",dir,name);f=fopen(path,"wb");fprintf(f,"P5\n160 100\n255\n");for(int i=0;i<16000;i++)fputc(n?(bg[i]&1?30:210):210,f);fclose(f);
 snprintf(path,sizeof path,"%s/%s.window",dir,name);f=fopen(path,"w");uint32_t gv=lng(gr_slot),range=lng(gv+160);for(int i=0;i<18;i++)fprintf(f,"%.17g\n",number(range+i*10));fclose(f);
 if(tihw.ram[gv+0x319]==5){uint32_t db=gv+0x2b6,nv=lng(db),ne=lng(db+6),table=lng(heap_slot),v=lng(table+word(db+4)*4),e=lng(table+word(db+10)*4);
  snprintf(path,sizeof path,"%s/%s.mesh",dir,name);f=fopen(path,"w");fprintf(f,"%u %u\n",nv,ne);if(nv<=4096&&v&&v+nv*10<tihw.ram_size)for(unsigned i=0;i<nv;i++)fprintf(f,"%d %d %d %d %d\n",(short)word(v+i*10),(short)word(v+i*10+2),(short)word(v+i*10+4),(short)word(v+i*10+6),(short)word(v+i*10+8));fclose(f);
  snprintf(path,sizeof path,"%s/%s.edges",dir,name);f=fopen(path,"w");if(ne<=10922&&e&&e+ne*8<tihw.ram_size)for(unsigned i=0;i<ne;i++)fprintf(f,"%u %u\n",lng(e+i*8),lng(e+i*8+4));fclose(f);
 }
 int32_t packets[8192*12];int np=graph89_copy_retained_text(lcd,packets,8192);
 snprintf(path,sizeof path,"%s/%s.packets",dir,name);f=fopen(path,"w");for(int i=0;i<np;i++){for(int k=0;k<12;k++)fprintf(f,"%d%c",packets[i*12+k],k==11?'\n':' ');}fclose(f);
 snprintf(path,sizeof path,"%s/%s.pixels",dir,name);f=fopen(path,"wb");for(int i=0;i<16000;i++)fputc(lcd[i]==30,f);fclose(f);
 snprintf(path,sizeof path,"%s/%s.overlay",dir,name);f=fopen(path,"wb");if(n)fwrite(bg,1,16000,f);fclose(f);
 fprintf(stderr,"flags %x style %d\n",word(lng(lng(gr_slot)+0x23e)),tihw.ram[lng(lng(gr_slot)+0x23e)+6]);
 fprintf(stderr,"%s: mode %d, %d points, %d geometry records, screen %d\n",name,tihw.ram[gv+0x319],(n-4)/2,nd/4,graph89_screen_is_on());
}
static int editor_cursor(void){uint8_t lcd[16000];int32_t p[8192*12];graph89_copy_screen(lcd);int n=graph89_copy_retained_text(lcd,p,8192);for(int i=0;i<n;i++)if(p[i*12+2]==8)return p[i*12];return -1;}
static void hold(const char *dir,const char *name,int key,double time,int frames){char path[4096];snprintf(path,sizeof path,"%s/%s.hold",dir,name);FILE *f=fopen(path,"w");graph89_cursor_test_time=time;graph89_key(key,1);for(int i=0;i<frames;i++){graph89_cursor_test_time=time+i*0.01;run(50000);fprintf(f,"%d %d %d\n",i,hdplot_trace_multiplier(),editor_cursor());}graph89_key(key,0);fclose(f);run(400000);}
int main(int argc,char **argv){
 if(argc<5)return 2;const char *rom=argv[1],*dir=argv[4];int mode=atoi(argv[2]),hd=atoi(argv[3]);if(mode<1||mode>6)return 2;mkdir(dir,0755);char path[4096];snprintf(path,sizeof path,"%s/rom.img",dir);if(graph89_start(rom,path))return 3;
 romcalls_get_symbol_address(0x10b,&gr_slot);uint32_t heap;romcalls_get_symbol_address(0x96,&heap);uint32_t off=heap-tihw.rom_base+10;heap_slot=(tihw.rom[off]<<24)|(tihw.rom[off+1]<<16)|(tihw.rom[off+2]<<8)|tihw.rom[off+3];
 uint8_t fonts[3*256*12];graph89_copy_font_templates(fonts);snprintf(path,sizeof path,"%s/fonts.bin",dir);FILE *ff=fopen(path,"wb");fwrite(fonts,1,sizeof fonts,ff);fclose(ff);
 graph89_retained_text_enable(1);graph89_hd_plot_enable(hd>0,hd?hd:8);
 if(argc>6 && !strcmp(argv[5],"inspect")){if(graph89_restore(argv[6]))return 7;run(50000);snapshot(dir,"loaded");tap(TIKEY_F4);run(300000000);snapshot(dir,"regraph");graph89_stop();return 0;}
 run(30000000);tap(TIKEY_HOME);tap(TIKEY_CLEAR);
 const char *names[]={"FUNCTION","PARAMETRIC","POLAR","SEQUENCE","3D","DIFF EQUATIONS"};char command[128];snprintf(command,sizeof command,"setMode(\"Graph\",\"%s\")\n",names[mode-1]);text(command);
 tap(TIKEY_DIAMOND);tap(TIKEY_F1);tap(TIKEY_CLEAR);
 const char *equations[]={"sin(x^2)","cos(t)\nsin(t)","2*cos(3*\x88)","n^2","sin(x)*cos(y)","y1\n1"};text(argc>5 && !strcmp(argv[5],"undefined") ? "sqrt(-1)" : argc>5 && !strcmp(argv[5],"clipped") ? "100*sin(x)*cos(y)" : equations[mode-1]);tap(TIKEY_ENTER1);snapshot(dir,"editor");
 if(mode==5 && argc>5 && (!strcmp(argv[5],"box")||!strcmp(argv[5],"hidden"))){uint32_t g=lng(gr_slot),m=lng(g+0x23e);if(!strcmp(argv[5],"box")){unsigned flags=(word(m)&~16)|8|4;tihw.ram[m]=flags>>8;tihw.ram[m+1]=flags;}else tihw.ram[m+6]=1;}
 int pending=argc>5 && (!strcmp(argv[5],"pending") || !strcmp(argv[5],"interrupt") || !strcmp(argv[5],"disable"));tap(TIKEY_DIAMOND);
 if(pending){graph89_key(TIKEY_F3,1);run(10000);int found=0;for(int i=0;i<200000;i++){uint32_t r=lng(lng(gr_slot)+160);if((mode<=3 && hdplot_pending()==2)||(mode==5&&number(r+20)>14)||(mode==6&&number(r+100)<0.1)){found=1;break;}run(500);}graph89_key(TIKEY_F3,0);if(!found)return 4;if(!strcmp(argv[5],"interrupt"))tap(TIKEY_ON);
 else if(!strcmp(argv[5],"disable"))graph89_hd_plot_enable(0,8);
 else {snprintf(path,sizeof path,"%s/pending.sav",dir);if(graph89_save(path)||graph89_restore(path))return 5;}}
 else tap(TIKEY_F3);
 run(300000000);snapshot(dir,"graph");
 if(pending){graph89_stop();return 0;}
 if(argc>5 && (!strcmp(argv[5],"undefined")||!strcmp(argv[5],"box")||!strcmp(argv[5],"hidden"))){graph89_stop();return 0;}
 snprintf(path,sizeof path,"%s/complete.sav",dir);if(graph89_save(path)||graph89_restore(path))return 6;run(50000);snapshot(dir,"restored");
 if(mode==5){tap(TIKEY_RIGHT);run(30000000);snapshot(dir,"rotated");}
 tap(TIKEY_RIGHT);snapshot(dir,"right");tap(TIKEY_LEFT);snapshot(dir,"left");tap(TIKEY_F3);snapshot(dir,"trace");if(argc>5 && !strcmp(argv[5],"clipped")){tap(TIKEY_RIGHT);run(50000000);}else if(argc>5 && !strcmp(argv[5],"stream")){
   uint8_t frame[16000];int32_t packets[8192*12];graph89_cursor_test_time=10;
   for(int move=0;move<8;move++){
    graph89_key(TIKEY_RIGHT,1);
    for(int j=0;j<1000;j++){run(500);graph89_copy_screen(frame);graph89_copy_retained_text(frame,packets,8192);}
    graph89_key(TIKEY_RIGHT,0);
    for(int j=0;j<500;j++){run(500);graph89_copy_screen(frame);graph89_copy_retained_text(frame,packets,8192);}
   }
  }else hold(dir,"trace",TIKEY_RIGHT,10,100);snapshot(dir,"held");tap(TIKEY_ESCAPE);if(argc>5 && !strcmp(argv[5],"clipped"))run(50000000);tap(TIKEY_F5);snapshot(dir,"menu");tap(TIKEY_ESCAPE);snapshot(dir,"closed");
 if(argc>5 && !strncmp(argv[5],"scroll-",7)){
  graph89_graph_cursor_speed(atoi(argv[5]+7));if(mode==5){tap(TIKEY_ON);run(30000000);}tap(TIKEY_HOME);tap(TIKEY_CLEAR);char equation[301];equation[0]=0;for(int i=0;i<20;i++)strcat(equation,i?"+sin(x^2)":"sin(x^2)");text(equation);
  hold(dir,"home",TIKEY_LEFT,20,100);snapshot(dir,"home-after");
  tap(TIKEY_DIAMOND);tap(TIKEY_F1);hold(dir,"y-down",TIKEY_DOWN,30,100);snapshot(dir,"y-down");
 }
 graph89_stop();return 0;
}
