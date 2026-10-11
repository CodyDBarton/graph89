/* Isolated ROM-backed plotting regression; never loads an app session. */
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
extern void (*graph89_instruction_trace)(uint32_t);
static uint32_t evaluator,return_pc,call_sp,axes;
static int evaluations,format_flags=-1;
static unsigned word_at(uint32_t a){return (tihw.ram[a]<<8)|tihw.ram[a+1];}
static uint32_t long_at(uint32_t a){return (word_at(a)<<16)|word_at(a+2);}
static void observe(uint32_t pc){
 uint32_t sp=m68k_areg(regs,7);
 if(pc==axes && format_flags>=0){uint32_t modes=long_at(long_at(sp+6)+0x23e);tihw.ram[modes]=format_flags>>8;tihw.ram[modes+1]=format_flags;}
 if(pc==evaluator){if(evaluations==0)fprintf(stderr,"Initial plot style %u\n",tihw.ram[m68k_areg(regs,6)-0x174]);return_pc=long_at(sp);call_sp=sp;}
 if(pc==return_pc && sp==call_sp+4)evaluations++;
}
static int progress_frames,progress_missing,progress_background_ink;
static void run(int n){graph89_run(n);}
static void plot_run(void){
 uint8_t pixels[16000],background[16000];float vectors[65540];
 for(int i=0;i<6000;i++){
  run(50000);graph89_copy_screen(pixels);
  int n=graph89_copy_hd_plot(pixels,vectors,65540,background);
  if(graph89_is_busy() && hdplot_pending() && evaluations>20){
   if(n){progress_frames++;for(int y=16;y<93;y++)for(int x=0;x<159;x++)if(background[y*160+x])progress_background_ink++;}
   else progress_missing++;
  }
 }
}
static void press(int key){graph89_key(key,1);run(400000);graph89_key(key,0);run(400000);}
static void snapshot(const char *dir,const char *name){char p[4096];uint8_t pixels[16000],background[16000];float vectors[65540],decorations[65536];
 graph89_copy_screen(pixels);int n=graph89_copy_hd_plot(pixels,vectors,65540,background);
 snprintf(p,sizeof p,"%s/%s.pgm",dir,name);FILE *f=fopen(p,"wb");fprintf(f,"P5\n160 100\n255\n");fwrite(pixels,1,16000,f);fclose(f);
 snprintf(p,sizeof p,"%s/%s.points",dir,name);f=fopen(p,"w");for(int i=0;i<n;i+=2)fprintf(f,"%.9g %.9g\n",vectors[i],vectors[i+1]);fclose(f);
 if(n){snprintf(p,sizeof p,"%s/%s.background.pgm",dir,name);f=fopen(p,"wb");fprintf(f,"P5\n160 100\n255\n");for(int i=0;i<16000;i++)background[i]=background[i]?30:210;fwrite(background,1,16000,f);fclose(f);}
 int nd=n?graph89_copy_hd_plot_decorations(decorations,65536):0;
 snprintf(p,sizeof p,"%s/%s.axes",dir,name);f=fopen(p,"w");for(int i=0;i<nd;i+=4)fprintf(f,"%.9g %.9g %.9g %.9g\n",decorations[i],decorations[i+1],decorations[i+2],decorations[i+3]);fclose(f);
 fprintf(stderr,"%s: %d vector values, %d evaluations, %d decorations\n",name,n,evaluations,nd/4);
}
int main(int argc,char **argv){
 if(argc!=5 && argc!=6)return 2;mkdir(argv[2],0755);char path[4096];snprintf(path,sizeof path,"%s/rom.img",argv[2]);
 if(graph89_start(argv[1],path))return 1;
 romcalls_get_symbol_address(0x1d1,&evaluator);romcalls_get_symbol_address(0x1b7,&axes);graph89_instruction_trace=observe;
 run(30000000);press(TIKEY_HOME);press(TIKEY_DIAMOND);press(TIKEY_F1);press(TIKEY_CLEAR);
 graph89_type_text(argv[4]);run(12000000+(int)strlen(argv[4])*400000);press(TIKEY_ENTER1);
 if(argc==6 && !strcmp(argv[5],"style")){press(TIKEY_UP);press(TIKEY_2ND);press(TIKEY_F1);press(TIKEY_2);}
 if(argc==6 && (!strcmp(argv[5],"window")||!strcmp(argv[5],"coarse"))){
  press(TIKEY_DIAMOND);press(TIKEY_F2);press(TIKEY_CLEAR);press(TIKEY_NEGATE);press(TIKEY_5);press(TIKEY_ENTER1);
  press(TIKEY_CLEAR);press(TIKEY_5);press(TIKEY_ENTER1);
  if(!strcmp(argv[5],"coarse")){for(int i=0;i<6;i++)press(TIKEY_DOWN);press(TIKEY_CLEAR);press(TIKEY_5);press(TIKEY_ENTER1);}
 }
 if(argc==6){if(!strcmp(argv[5],"grid"))format_flags=0x20;else if(!strcmp(argv[5],"axes-off"))format_flags=0x10;else if(!strcmp(argv[5],"box"))format_flags=0x08;else if(!strcmp(argv[5],"labels"))format_flags=0x04;}
 graph89_hd_plot_enable(atoi(argv[3])>0,atoi(argv[3]));
 press(TIKEY_DIAMOND);press(TIKEY_F3);
 if(argc==6 && (!strcmp(argv[5],"resume")||!strcmp(argv[5],"disable")||!strcmp(argv[5],"interrupt"))){
  int found=0;for(int i=0;i<2000;i++){if(hdplot_pending()==2){found=1;break;}run(5000);}
  if(!found){fprintf(stderr,"No pending additional evaluation\n");return 3;}
  snprintf(path,sizeof path,"%s/pending.sav",argv[2]);if(graph89_save(path))return 4;
  if(!strcmp(argv[5],"resume")){graph89_hd_plot_enable(0,8);if(graph89_restore(path))return 5;}
  else if(!strcmp(argv[5],"disable"))graph89_hd_plot_enable(0,8);
  else if(!strcmp(argv[5],"interrupt"))press(TIKEY_ON);
 }
 if(argc==6 && !strcmp(argv[5],"progress"))plot_run();else run(300000000);
 snapshot(argv[2],"graph");
 if(argc==6 && !strncmp(argv[5],"incremental",11)){
  if(!strcmp(argv[5],"incremental-restored")){snprintf(path,sizeof path,"%s/first.sav",argv[2]);if(graph89_save(path))return 8;graph89_hd_plot_enable(0,8);if(graph89_restore(path))return 9;graph89_hd_plot_enable(atoi(argv[3])>0,8);}
  press(TIKEY_DIAMOND);press(TIKEY_F1);press(TIKEY_CLEAR);
  graph89_type_text("cos(x)");run(16000000);press(TIKEY_ENTER1);
  press(TIKEY_DIAMOND);press(TIKEY_F3);plot_run();snapshot(argv[2],"incremental");
 }
 if(argc==6 && (!strncmp(argv[5],"incremental",11)||!strcmp(argv[5],"progress"))){
  snprintf(path,sizeof path,"%s/progress.txt",argv[2]);FILE *f=fopen(path,"w");fprintf(f,"%d %d %d\n",progress_frames,progress_missing,progress_background_ink);fclose(f);
 }
 press(TIKEY_F4);run(300000000);snapshot(argv[2],"regraph");
 if(argc==5 && atoi(argv[3])>0){
  snprintf(path,sizeof path,"%s/complete.sav",argv[2]);if(graph89_save(path))return 6;
  graph89_hd_plot_enable(0,8);if(graph89_restore(path))return 7;graph89_hd_plot_enable(1,8);snapshot(argv[2],"restored");
 }
 press(TIKEY_F1);snapshot(argv[2],"menu");press(TIKEY_ESCAPE);snapshot(argv[2],"returned");
 graph89_hd_plot_enable(0,8);snapshot(argv[2],"disabled");
 press(TIKEY_HOME);snapshot(argv[2],"home");
 graph89_stop();return 0;
}
