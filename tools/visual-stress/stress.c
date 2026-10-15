/* Isolated, intermediate-frame visual exploration. Never reads app state. */
#include <stdlib.h>
#include "Graph89Core.h"
#include "ti68k_def.h"
#include "keydefs.h"
#include "libuae.h"
#include "romcalls.h"
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
extern double graph89_cursor_test_time;
extern void (*graph89_instruction_trace)(uint32_t);
static const char *folder,*phase="boot";
static unsigned serial,samples,action;
static FILE *sequence;
static unsigned font_slot,port_slot,chars[3];
static unsigned char previous[16000];static int32_t prior[8192*12];static int prior_count=-1;
typedef struct {unsigned pc,sp;int x,y,w,h,font,code,attr;} Pending;
static Pending pending[32];
static unsigned word(unsigned a){if(a+2<tihw.ram_size)return tihw.ram[a]*256+tihw.ram[a+1];if(a>=tihw.rom_base&&a+2<tihw.rom_base+tihw.rom_size){a-=tihw.rom_base;return tihw.rom[a]*256+tihw.rom[a+1];}return 0;}
static unsigned lng(unsigned a){return word(a)*65536+word(a+2);}
static int byte(unsigned a){if(a<tihw.ram_size)return tihw.ram[a];if(a>=tihw.rom_base&&a<tihw.rom_base+tihw.rom_size)return tihw.rom[a-tihw.rom_base];return -1;}
static unsigned rom(unsigned id){unsigned a=0;romcalls_get_symbol_address(id,&a);return a;}
static unsigned char templates[3*256*12];
static void observe(unsigned pc){
 unsigned sp=m68k_areg(regs,7),a=sp+4;
 for(int k=0;k<32;k++)if(pending[k].pc && ((pc==pending[k].pc&&sp==pending[k].sp)||sp>pending[k].sp))pending[k].pc=0;
 if(pc==rom(0x1e) && !strcmp(phase,"format-open")) {
  unsigned r=lng(a+4);fprintf(sequence,"WINOPEN %x flags %x rect",lng(a),word(a+8));for(int i=0;i<4;i++)fprintf(sequence," %d",(short)word(r+i*2));fputc('\n',sequence);
 }
 if(lng(port_slot)!=tihw.lcd_adr)return;
 int f=byte(font_slot);if(f<0||f>2)return;
 for(int k=0;k<3;k++)if(pc==chars[k]){
  int x=(short)word(a)+(f<2),y=(short)word(a+2),c=k==2?0:word(a+4)&255,w=0;
  if(k==2){unsigned s=lng(a+4);for(int i=0;i<256;i++){int ch=byte(s+i);if(ch<=0)break;w+=templates[(f*256+ch)*12];}}
  else w=templates[(f*256+c)*12];
  for(int i=0;i<32;i++)if(!pending[i].pc){pending[i]=(Pending){lng(sp),sp+4,x,y,w,(int[]){5,8,10}[f],f,c,(short)word(a+(k==0?6:k==1?10:8))};break;}
 }
}
static void capture(int force){
 if(!force&&samples>=48)return;
 unsigned char pixels[16000];int32_t cells[8192*12];graph89_copy_screen(pixels);
 int n=graph89_copy_retained_text(pixels,cells,8192);
 if(!force&&n==prior_count&&!memcmp(pixels,previous,sizeof pixels)&&!memcmp(cells,prior,n*12*4))return;
 memcpy(previous,pixels,sizeof pixels);memcpy(prior,cells,n*12*4);prior_count=n;
 char path[4096];unsigned id=serial++;samples++;
 snprintf(path,sizeof path,"%s/%05u-%s.pgm",folder,id,phase);FILE *f=fopen(path,"wb");fprintf(f,"P5\n160 100\n255\n");fwrite(pixels,1,16000,f);fclose(f);
 snprintf(path,sizeof path,"%s/%05u-%s.cells.json",folder,id,phase);f=fopen(path,"w");fputc('[',f);for(int i=0;i<n;i++){fprintf(f,"%s[",i?",":"");for(int j=0;j<12;j++)fprintf(f,"%s%d",j?",":"",cells[i*12+j]);fputc(']',f);}fputs("]\n",f);fclose(f);
 snprintf(path,sizeof path,"%s/%05u-%s.pending.json",folder,id,phase);f=fopen(path,"w");fputc('[',f);int first=1;for(int k=0;k<32;k++)if(pending[k].pc){Pending*p=pending+k;fprintf(f,"%s[%d,%d,%d,%d,%d,%d,%d]",first?"":",",p->x,p->y,p->w,p->h,p->font,p->code,p->attr);first=0;}fputs("]\n",f);fclose(f);
 static float plot[65540],decorations[65536];static unsigned char background[16000];
 int np=graph89_copy_hd_plot(pixels,plot,65540,background),nd=np?graph89_copy_hd_plot_decorations(decorations,65536):0;
 if(np>6){snprintf(path,sizeof path,"%s/%05u-%s.hdplot",folder,id,phase);f=fopen(path,"wb");fwrite(&np,4,1,f);fwrite(&nd,4,1,f);fwrite(background,1,16000,f);fwrite(plot,4,np,f);fwrite(decorations,4,nd,f);fclose(f);}

}
static void begin(const char *name){phase=name;samples=0;action++;fprintf(sequence,"%u %u %s",action,serial,name);}
static void run(int n){while(n>0){int k=n>20000?20000:n;graph89_run(k);n-=k;if(strcmp(phase,"boot"))capture(0);}}
static void tap(const char *name,int key){if(key==TIKEY_F6 || key==TIKEY_F7 || key==TIKEY_F8){int actual=key==TIKEY_F6?TIKEY_F1:key==TIKEY_F7?TIKEY_F2:TIKEY_F3;tap("2nd-modifier",TIKEY_2ND);key=actual;}begin(name);fprintf(sequence," key %d\n",key);graph89_cursor_test_time+=0.2;graph89_key(key,1);run(400000);graph89_cursor_test_time+=0.1;graph89_key(key,0);run(1000000);capture(1);}
static void type(const char *name,const char *text){begin(name);fprintf(sequence," text ");for(const unsigned char*p=(const unsigned char*)text;*p;p++)fprintf(sequence,"%02x",*p);fputc('\n',sequence);graph89_type_text(text);run(12000000+(int)strlen(text)*400000);int drained=0;for(int i=0;i<10000;i++){run(100000);if(graph89_type_text("")){drained=1;break;}}if(!drained){fprintf(stderr,"Input queue did not drain\n");exit(5);}run(4000000);capture(1);}
static void home(void){tap("home",TIKEY_HOME);tap("history-exit",TIKEY_ESCAPE);tap("history-exit",TIKEY_ESCAPE);tap("clear",TIKEY_CLEAR);tap("clear",TIKEY_CLEAR);}
static void menu(const char *name,int key){tap(name,key);for(int i=0;i<3;i++)tap("menu-down",TIKEY_DOWN);tap("submenu-right",TIKEY_RIGHT);tap("submenu-left",TIKEY_LEFT);tap("menu-close",TIKEY_ESCAPE);tap("menu-close",TIKEY_ESCAPE);}
static void combo(const char *name,int modifier,int key){tap("modifier",modifier);tap(name,key);}
int main(int argc,char **argv){
 if(argc<3)return 2;folder=argv[2];mkdir(folder,0755);char path[4096];snprintf(path,sizeof path,"%s/stress.img",folder);if(graph89_start(argv[1],path))return 3;
 snprintf(path,sizeof path,"%s/actions.txt",folder);sequence=fopen(path,"w");graph89_cursor_test_time=0;graph89_retained_text_enable(argc>3 && !strcmp(argv[argc-1],"original")?0:1);graph89_hd_plot_enable(1,8);graph89_copy_font_templates(templates);snprintf(path,sizeof path,"%s/fonts.bin",folder);FILE*f=fopen(path,"wb");fwrite(templates,1,sizeof templates,f);fclose(f);
 unsigned getter=rom(0x18e),restore=rom(0x1a3);font_slot=lng(getter+2);port_slot=lng(restore+6);chars[0]=rom(0x1a4);chars[1]=rom(0x191);chars[2]=rom(0x1a9);graph89_instruction_trace=observe;
 run(30000000);home();
 if(argc>3 && !strcmp(argv[3],"errors-fast")) {
  graph89_type_text("1/sin(x^2)\n(12345+67890)^2\nsqrt(2)\nlcm(20,30,40)\n");
  begin("queued-lcm-error");fprintf(sequence," wait\n");run(100000000);capture(1);
  tap("queued-lcm-dismiss",TIKEY_ESCAPE);tap("queued-lcm-clear",TIKEY_CLEAR);tap("queued-lcm-select",TIKEY_UP);
  fclose(sequence);graph89_instruction_trace=0;printf("%u actions; %u intermediate/settled frames\n",action,serial);graph89_stop();return 0;
 }
 if(argc>3 && (!strcmp(argv[3],"rotation") || !strcmp(argv[3],"rotation-format"))) {
  type("rotation-mode","setMode(\"Graph\",\"3D\")\nsetGraph(\"Style\",\"Wire Frame\")\nsetGraph(\"Axes\",\"Axes\")\nsetGraph(\"Labels\",\"On\")\n");
  combo("rotation-editor",TIKEY_DIAMOND,TIKEY_F1);tap("rotation-clear",TIKEY_CLEAR);
  type("rotation-equation","sin(x)*cos(y)");tap("rotation-enter",TIKEY_ENTER1);
  combo("rotation-graph",TIKEY_DIAMOND,TIKEY_F3);run(180000000);
  for(int i=0;i<400 && graph89_is_busy();i++)run(10000000);
  begin("rotation-ready");capture(1);
  if(!strcmp(argv[3],"rotation-format")) {
   tap("format-tools",TIKEY_F1);tap("format-open",TIKEY_9);
   begin("format-idle");run(12000000);capture(1);
   tap("format-close",TIKEY_ESCAPE);begin("format-restored");run(12000000);capture(1);
   fclose(sequence);graph89_instruction_trace=0;printf("%u actions; %u intermediate/settled frames\n",action,serial);graph89_stop();return 0;
  }
  begin("rotation-hold");graph89_key(TIKEY_RIGHT,1);
  for(int i=0;i<96;i++){graph89_cursor_test_time+=1.0/120;run(200000);capture(1);}
  graph89_key(TIKEY_RIGHT,0);begin("rotation-auto");
  for(int i=0;i<240;i++){graph89_cursor_test_time+=1.0/120;run(200000);capture(1);}
  tap("rotation-stop",TIKEY_ESCAPE);
  begin("rotation-stopped");for(int i=0;i<30;i++){graph89_cursor_test_time+=1.0/120;run(200000);capture(1);}
  fclose(sequence);graph89_instruction_trace=0;printf("%u actions; %u intermediate/settled frames\n",action,serial);graph89_stop();return 0;
 }
 if(argc>3 && !strcmp(argv[3],"catalog-help")) {
  tap("catalog-open",TIKEY_CATALOG);
  tap("catalog-built-in",TIKEY_F2);
  for(int i=0;i<10;i++) {
   tap("catalog-help-open",TIKEY_F1);
   begin("catalog-help-idle");fprintf(sequence," wait\n");run(4000000);capture(1);
   tap("catalog-help-close",TIKEY_ESCAPE);
   tap("catalog-next",TIKEY_DOWN);
  }
  tap("catalog-e",TIKEY_DIVIDE);
  tap("catalog-help-e",TIKEY_F1);tap("catalog-help-e-close",TIKEY_ESCAPE);
  tap("catalog-p",TIKEY_MINUS);
  tap("catalog-help-p",TIKEY_F1);tap("catalog-help-p-close",TIKEY_ESCAPE);
  tap("catalog-close",TIKEY_ESCAPE);
  fclose(sequence);graph89_instruction_trace=0;printf("%u actions; %u intermediate/settled frames\n",action,serial);graph89_stop();return 0;
 }
 const char *math[]={"1/sin(x^2)","sqrt(1/(1+x^2))","(x^2+1)/(x^3-1)","sin(x)^(-1)+cos(x)^(-1)","sum(k^2,k,1,8)","[[1,2][3,4]]","{1,2,3,4}"};
 for(int i=0;i<7;i++){tap("clear-input",TIKEY_CLEAR);type("math-input",math[i]);tap("math-evaluate",TIKEY_ENTER1);tap("history-up",TIKEY_UP);tap("history-up",TIKEY_UP);tap("history-down",TIKEY_DOWN);tap("history-exit",TIKEY_ESCAPE);}
 if(argc>3 && !strcmp(argv[3],"errors")) {
  for(int i=0;i<5;i++) {
   home();type("lcm-error-input","lcm(20,30,40)");tap("lcm-error-show",TIKEY_ENTER1);
   begin("lcm-error-idle");fprintf(sequence," wait\n");run(12000000);capture(1);
   tap("lcm-error-dismiss",TIKEY_ESCAPE);tap("lcm-error-clear",TIKEY_CLEAR);
   for(int j=0;j<4;j++)tap("lcm-history-up",TIKEY_UP);
   for(int j=0;j<4;j++)tap("lcm-history-down",TIKEY_DOWN);
   tap("lcm-history-exit",TIKEY_ESCAPE);menu("lcm-tools",TIKEY_F1);
   type("lcm-valid-input","lcm(20,30)");tap("lcm-valid-evaluate",TIKEY_ENTER1);
  }
  fclose(sequence);graph89_instruction_trace=0;printf("%u actions; %u intermediate/settled frames\n",action,serial);graph89_stop();return 0;
 }
 for(int i=0;i<6;i++){int keys[]={TIKEY_F1,TIKEY_F2,TIKEY_F3,TIKEY_F4,TIKEY_F5,TIKEY_F6};menu("home-toolbar",keys[i]);}
 tap("catalog-open",TIKEY_CATALOG);for(int i=0;i<8;i++)tap("catalog-down",TIKEY_DOWN);tap("catalog-e",TIKEY_DIVIDE);for(int i=0;i<4;i++)tap("catalog-down",TIKEY_DOWN);tap("catalog-p",TIKEY_MINUS);tap("catalog-close",TIKEY_ESCAPE);
 menu("mode-open",TIKEY_MODE);combo("varlink-open",TIKEY_2ND,TIKEY_MINUS);tap("varlink-close",TIKEY_ESCAPE);combo("math-menu",TIKEY_2ND,TIKEY_5);for(int i=0;i<6;i++)tap("math-category-down",TIKEY_DOWN);tap("math-submenu",TIKEY_RIGHT);tap("math-item-down",TIKEY_DOWN);tap("math-close",TIKEY_ESCAPE);tap("math-close",TIKEY_ESCAPE);
 home();tap("clear-error",TIKEY_CLEAR);type("intentional-error","1+");tap("error-show",TIKEY_ENTER1);tap("error-close",TIKEY_ESCAPE);tap("clear-error",TIKEY_CLEAR);
 char clean[4096];snprintf(clean,sizeof clean,"%s/clean.state",folder);graph89_save(clean);
 const char *modes[]={"FUNCTION","PARAMETRIC","POLAR","SEQUENCE","3D","DIFF EQUATIONS"};const char*equations[]={"sin(x)\ncos(x)","cos(t)\nsin(t)","2*cos(3*\x88)","n^2","sin(x)*cos(y)","y1\n1"};
 for(int mode=0;mode<6;mode++){
  if(graph89_restore(clean))return 4;memset(pending,0,sizeof pending);char command[160];snprintf(command,sizeof command,"setMode(\"Graph\",\"%s\")\n",modes[mode]);home();type("graph-mode",command);
  int actual_mode=byte(lng(rom(0x10b))+0x319);fprintf(sequence,"MODE %d expected %d\n",actual_mode,mode+1);if(actual_mode!=mode+1){fprintf(stderr,"Mode switch failed: %d not %d\n",actual_mode,mode+1);return 6;}
  combo("equation-editor",TIKEY_DIAMOND,TIKEY_F1);tap("equation-clear",TIKEY_CLEAR);type("equation-input",equations[mode]);tap("equation-enter",TIKEY_ENTER1);for(int i=0;i<4;i++)tap("equation-down",TIKEY_DOWN);for(int i=0;i<4;i++)tap("equation-up",TIKEY_UP);
  combo("window-editor",TIKEY_DIAMOND,TIKEY_F2);menu("window-toolbar",TIKEY_F1);combo("graph-open",TIKEY_DIAMOND,TIKEY_F3);begin("graph-progress");fprintf(sequence," wait\n");run(180000000);for(int i=0;i<300 && graph89_is_busy();i++)run(10000000);fprintf(sequence,"GRAPH %d busy %d\n",mode+1,graph89_is_busy());if(graph89_is_busy()){fprintf(stderr,"Graph did not finish in mode %d\n",mode+1);return 7;}capture(1);
  for(int i=0;i<4;i++)tap("graph-right",TIKEY_RIGHT);tap("graph-trace",TIKEY_F3);for(int i=0;i<6;i++)tap("trace-right",TIKEY_RIGHT);tap("trace-exit",TIKEY_ESCAPE);
  menu("graph-zoom",TIKEY_F2);menu("graph-math",TIKEY_F5);
  if(mode==0){tap("math-intersection-menu",TIKEY_F5);tap("intersection-first-curve",TIKEY_5);tap("intersection-second-curve",TIKEY_ENTER1);tap("intersection-lower-bound",TIKEY_ENTER1);for(int i=0;i<8;i++)tap("bound-left",TIKEY_LEFT);tap("intersection-upper-bound",TIKEY_ENTER1);for(int i=0;i<20;i++)tap("bound-right",TIKEY_RIGHT);tap("intersection-result",TIKEY_ENTER1);begin("intersection-computing");fprintf(sequence," wait\n");run(40000000);for(int i=0;i<100 && graph89_is_busy();i++)run(10000000);capture(1);tap("intersection-close",TIKEY_ESCAPE);}
 tap("table-home",TIKEY_HOME);combo("table-view",TIKEY_DIAMOND,TIKEY_F5);for(int i=0;i<4;i++)tap("table-down",TIKEY_DOWN);tap("table-return",TIKEY_HOME);
 }
 fclose(sequence);graph89_instruction_trace=0;printf("%u actions; %u intermediate/settled frames\n",action,serial);graph89_stop();return 0;
}
