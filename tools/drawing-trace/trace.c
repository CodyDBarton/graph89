/* Read-only TI-68k drawing-call observer. Host harness, never linked into apps. */
#include <stdlib.h>
#include "Graph89Core.h"
#include "ti68k_def.h"
#include "keydefs.h"
#include "libuae.h"
#include "romcalls.h"
#include "hdtext.h"
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#ifdef GRAPH89_DRAW_TRACE
extern void (*graph89_instruction_trace)(uint32_t);
#endif

typedef struct { unsigned id; const char *name; uint32_t address; unsigned count; } Call;
static Call calls[] = {
 {0x009,"WinCharXY",0,0},{0x00a,"WinChar",0,0},{0x00c,"WinClr",0,0},
 {0x013,"WinFont",0,0},{0x023,"WinScrollH",0,0},{0x024,"WinScrollV",0,0},
 {0x025,"WinStr",0,0},{0x026,"WinStrXY",0,0},{0x04a,"Parse2DExpr",0,0},
 {0x04c,"Print2DExpr",0,0},{0x185,"BitmapGet",0,0},{0x187,"BitmapPut",0,0},
 {0x189,"ScrRectFill",0,0},{0x18b,"ScrRectScroll",0,0},{0x18c,"ScrRectShift",0,0},
 {0x18e,"FontGetSys",0,0},{0x18f,"FontSetSys",0,0},{0x191,"DrawClipChar",0,0},
 {0x193,"DrawClipLine",0,0},{0x195,"DrawClipRect",0,0},{0x19a,"SetCurAttr",0,0},
 {0x19b,"SetCurClip",0,0},{0x19e,"ClrScr",0,0},{0x1a0,"SaveScrState",0,0},
 {0x1a1,"RestoreScrState",0,0},{0x1a2,"PortSet",0,0},{0x1a3,"PortRestore",0,0},
 {0x1a4,"DrawChar",0,0},{0x1a5,"DrawFkey",0,0},{0x1a6,"DrawIcon",0,0},
 {0x1a7,"DrawLine",0,0},{0x1a8,"DrawPix",0,0},{0x1a9,"DrawStr",0,0},
 {0x5db,"WinStrXYWrap",0,0}
};
#define N_CALLS (sizeof(calls)/sizeof(calls[0]))
/* Page filter avoids searching the table on most executed instructions. */
static unsigned char pages[65536];
static FILE *events;
static const char *phase="boot";
static unsigned long long instruction, sequence;
static int font_hint=-1;
static uint32_t port_hint, font_slot, port_slot;

/* No hw_get_* reads: direct backing bytes cannot trigger guest IO/flash effects. */
static int byte_at(uint32_t a) {
    if(a < tihw.ram_size) return tihw.ram[a];
    if(a >= tihw.rom_base && a-tihw.rom_base < tihw.rom_size) return tihw.rom[a-tihw.rom_base];
    return -1;
}
static unsigned word_at(uint32_t a) { int h=byte_at(a),l=byte_at(a+1); return h<0||l<0?0:((unsigned)h<<8)|l; }
static uint32_t long_at(uint32_t a) { return (word_at(a)<<16)|word_at(a+2); }
static void hex_bytes(FILE *f,uint32_t a,unsigned n) {
    fputc('"',f);
    for(unsigned i=0;i<n;i++) { int b=byte_at(a+i); if(b<0) break; fprintf(f,"%02x",b); }
    fputc('"',f);
}
static void string_bytes(FILE *f,uint32_t a) {
    fputc('"',f);
    for(unsigned i=0;i<256;i++) { int b=byte_at(a+i); if(b<=0) break; fprintf(f,"%02x",b); }
    fputc('"',f);
}
static void observe(uint32_t pc) {
    instruction++;
    if(!pages[(pc&0xffffff)>>8]) return;
    for(unsigned i=0;i<N_CALLS;i++) {
        Call *c=&calls[i];
        if(pc!=c->address) continue;
        c->count++;
        uint32_t sp=m68k_areg(regs,7),a=sp+4;
        if(c->id==0x18f) font_hint=(short)word_at(a);
        if(c->id==0x1a2) port_hint=long_at(a);
        if(c->id==0x1a3) port_hint=0x4c00;
        fprintf(events,"{\"font\":%d,\"port\":%u,\"seq\":%llu,\"instruction\":%llu,\"phase\":\"%s\",\"call\":\"%s\",\"id\":%u,\"pc\":%u,\"sp\":%u,\"return_pc\":%u,\"font_hint\":%d,\"port_hint\":%u,\"lcd_address\":%u,\"stack_hex\":",font_slot?byte_at(font_slot):-1,port_slot?long_at(port_slot):0,++sequence,instruction,phase,c->name,c->id,pc,sp,long_at(sp),font_hint,port_hint,tihw.lcd_adr);
        hex_bytes(events,a,40);
        fprintf(events,",\"registers\":[");
        for(unsigned r=0;r<16;r++) fprintf(events,"%s%u",r?",":"",regs.regs[r]);
        fprintf(events,"]");
        switch(c->id) {
          case 0x191: case 0x1a4: case 0x1a5:
            fprintf(events,",\"x\":%d,\"y\":%d,\"character\":%u,\"attr\":%d",(short)word_at(a),(short)word_at(a+2),word_at(a+4)&255,(short)word_at(a+(c->id==0x191?10:6)));
            if(c->id==0x191) { fprintf(events,",\"clip_hex\":"); hex_bytes(events,long_at(a+6),4); }
            break;
          case 0x1a9:
            fprintf(events,",\"x\":%d,\"y\":%d,\"attr\":%d,\"text_hex\":",(short)word_at(a),(short)word_at(a+2),(short)word_at(a+8)); string_bytes(events,long_at(a+4)); break;
          case 0x1a7:
            fprintf(events,",\"x0\":%d,\"y0\":%d,\"x1\":%d,\"y1\":%d,\"attr\":%d",(short)word_at(a),(short)word_at(a+2),(short)word_at(a+4),(short)word_at(a+6),(short)word_at(a+8));break;
          case 0x1a8:
            fprintf(events,",\"x\":%d,\"y\":%d,\"attr\":%d",(short)word_at(a),(short)word_at(a+2),(short)word_at(a+4));break;
          case 0x04c:
            fprintf(events,",\"expression\":%u,\"window\":%u,\"x\":%d,\"y\":%d,\"expression_hex\":",long_at(a),long_at(a+4),(short)word_at(a+8),(short)word_at(a+10));hex_bytes(events,long_at(a),48);break;
          case 0x025: case 0x026: case 0x5db:
            fprintf(events,",\"window\":%u,\"window_hex\":",long_at(a));hex_bytes(events,long_at(a),40);
            if(c->id!=0x025) fprintf(events,",\"x\":%d,\"y\":%d",(short)word_at(a+4),(short)word_at(a+6));
            fprintf(events,",\"text_hex\":");string_bytes(events,long_at(a+(c->id==0x025?4:8)));break;
        }
        fputs("}\n",events);
    }
}
#ifdef GRAPH89_DRAW_TRACE
static unsigned mid_draw_probes;
static void sample_during_drawing(uint32_t pc) {
    if(!pages[(pc&0xffffff)>>8])return;
    uint32_t pixel=0;for(unsigned i=0;i<N_CALLS;i++)if(calls[i].id==0x1a8){pixel=calls[i].address;break;}
    if(pc!=pixel || (strcmp(phase,"clipped-math-pretty") && strcmp(phase,"tall-integral-pretty")))return;
    uint8_t pixels[16000];int32_t packets[1024*12];graph89_copy_screen(pixels);
    for(int i=0;i<16000;i++)pixels[i]=pixels[i]==30;
    /* The observer runs inside the CPU batch lock. Sample each unfinished cap
       exactly as a host frame can, without recursively acquiring that lock. */
    hdtext_copy_locked(pixels,packets,1024);mid_draw_probes++;
}
#endif
static void run(unsigned n) { graph89_run(n); }
static void press(int key) { graph89_key(key,1);run(400000);graph89_key(key,0);run(400000); }
static void snapshot(const char *dir,const char *name) {
    char p[4096];snprintf(p,sizeof(p),"%s/%s.pgm",dir,name);
    uint8_t pixels[16000];graph89_copy_screen(pixels);
    int32_t packets[1024*12];int count=graph89_copy_retained_text(pixels,packets,1024);
    char metadata[4096];snprintf(metadata,sizeof(metadata),"%s/%s.cells.json",dir,name);
    FILE *m=fopen(metadata,"wb");if(!m)exit(1);fputs("[",m);
    for(int i=0;i<count;i++){fprintf(m,"%s[",i?",":"");for(int j=0;j<12;j++)fprintf(m,"%s%d",j?",":"",packets[i*12+j]);fputs("]",m);}fputs("]\n",m);fclose(m);
    FILE *f=fopen(p,"wb");if(!f){perror(p);exit(1);}fprintf(f,"P5\n160 100\n255\n");fwrite(pixels,1,sizeof(pixels),f);fclose(f);
}
static void check_clipped_capture(void) {
    uint8_t pixels[16000],test[16000];int32_t cells[1024*12],c[12];
    graph89_copy_screen(pixels);int n=graph89_copy_retained_text(pixels,cells,1024),found=0;
    for(int i=0;i<n;i++)if(cells[i*12+2]==3 && cells[i*12+3]==189 && cells[i*12+1]<cells[i*12+9]) {
        memcpy(c,cells+i*12,sizeof c);found=1;break;
    }
    if(!found){fprintf(stderr,"Missing top-clipped integral geometry\n");exit(1);}
    memcpy(test,pixels,sizeof test);
    /* Pixels outside the guest clip must not affect this retained identity. */
    for(int y=0;y<c[9];y++)for(int x=c[0];x<c[0]+c[5];x++)test[y*160+x]=test[y*160+x]==30?210:30;
    n=graph89_copy_retained_text(test,cells,1024);found=0;
    for(int i=0;i<n;i++)if(cells[i*12+2]==3 && cells[i*12+3]==189 && cells[i*12+1]==c[1])found=1;
    if(!found){fprintf(stderr,"Hidden pixels invalidated clipped shape\n");exit(1);}
    memcpy(test,pixels,sizeof test);
    for(int y=c[9];y<c[11] && y<c[1]+c[6];y++)for(int x=c[0];x<c[0]+c[5];x++)test[y*160+x]=test[y*160+x]==30?210:30;
    n=graph89_copy_retained_text(test,cells,1024);found=0;
    for(int i=0;i<n;i++)if(cells[i*12+2]==3 && cells[i*12+3]==189 && cells[i*12+4]==(c[4]^1) && cells[i*12+6]==c[6])found=1;
    if(!found){fprintf(stderr,"Clipped shape inversion failed\n");exit(1);}
    for(int y=c[9];y<c[11] && y<c[1]+c[6];y++)for(int x=c[0];x<c[0]+c[5];x++)test[y*160+x]=210;
    n=graph89_copy_retained_text(test,cells,1024);
    for(int i=0;i<n;i++)if(cells[i*12+2]==3 && cells[i*12+3]==189 && cells[i*12+1]==c[1]) {
        fprintf(stderr,"Cleared clipped shape survived validation\n");exit(1);
    }
}
static void text(const char *s) { if(!graph89_type_text(s)) {fprintf(stderr,"Text injection failed\n");exit(1);}run(12000000+(unsigned)strlen(s)*400000); }
int main(int argc,char **argv) {
    if(argc!=4) {fprintf(stderr,"Usage: drawing-trace OS.89u scratch-directory observe|control|retained\n");return 2;}
    int trace=!strcmp(argv[3],"observe");
    int retained=!strcmp(argv[3],"retained");
    if(!trace && !retained && strcmp(argv[3],"control"))return 2;
#ifndef GRAPH89_DRAW_TRACE
    if(trace){fprintf(stderr,"Observer not compiled in\n");return 2;}
#endif
    mkdir(argv[2],0755);char path[4096];snprintf(path,sizeof(path),"%s/rom.img",argv[2]);
    int err=graph89_start(argv[1],path);if(err){fprintf(stderr,"Boot error %d\n",err);return 1;}
    uint32_t base,size;romcalls_get_table_infos(&base,&size);
    snprintf(path,sizeof(path),"%s/events.jsonl",argv[2]);events=fopen(path,"wb");if(!events)return 1;
    snprintf(path,sizeof(path),"%s/calls.json",argv[2]);FILE *map=fopen(path,"wb");if(!map)return 1;
    fprintf(map,"{\"rom_version\":\"%s\",\"model\":%d,\"rom_base\":%u,\"table_base\":%u,\"table_size\":%u,\"calls\":[",tihw.rom_version,tihw.calc_type,tihw.rom_base,base,size);
    for(unsigned i=0;i<N_CALLS;i++) {
        if(calls[i].id<size)romcalls_get_symbol_address(calls[i].id,&calls[i].address);
        if(calls[i].address)pages[(calls[i].address&0xffffff)>>8]=1;
        fprintf(map,"%s{\"name\":\"%s\",\"id\":%u,\"address\":%u}",i?",":"",calls[i].name,calls[i].id,calls[i].address);
    }
    /* Derive live globals only from verified tiny accessor instruction patterns.
       FontGetSys: MOVE.B (absolute long),D0; RTS.
       PortRestore: MOVE.L #LCD_MEM,(absolute long). Unknown ROMs keep state unknown. */
    for(unsigned i=0;i<N_CALLS;i++) {
        uint32_t pc=calls[i].address;
        if(calls[i].id==0x18e && word_at(pc)==0x1039 && word_at(pc+6)==0x4e75)
            font_slot=long_at(pc+2);
        if(calls[i].id==0x1a3 && word_at(pc)==0x23fc && long_at(pc+2)==0x4c00)
            port_slot=long_at(pc+6);
    }
    fprintf(map,"],\"font_slot\":%u,\"port_slot\":%u}\n",font_slot,port_slot);fclose(map);
#ifdef GRAPH89_DRAW_TRACE
    if(trace)graph89_instruction_trace=observe;
    else if(retained)graph89_instruction_trace=sample_during_drawing;
#endif
    graph89_retained_text_enable(retained);
    clock_t start=clock();
    run(30000000);snapshot(argv[2],"00-boot");
    phase="home";press(TIKEY_HOME);press(TIKEY_CLEAR);snapshot(argv[2],"01-home");
    phase="input";text("1/sin(x^2)");snapshot(argv[2],"02-input");
    if(retained) {
        uint8_t pixels[16000];graph89_copy_screen(pixels);int32_t packets[1024*12];
        int n=graph89_copy_retained_text(pixels,packets,1024),found=0;
        for(int i=0;i<n;i++)if(packets[i*12+3]==49 && packets[i*12+1]==85) {
            int x=packets[i*12],y=packets[i*12+1],w=packets[i*12+5],h=packets[i*12+6];
            for(int row=0;row<h;row++)pixels[(y+row)*160+x+w-1]=30;
            n=graph89_copy_retained_text(pixels,packets,1024);
            for(int j=0;j<n;j++)if(packets[j*12]==x && packets[j*12+1]==y && packets[j*12+3]==49)found=1;
            break;
        }
        if(!found){fprintf(stderr,"Cursor retention failed\n");return 1;}
    }
    phase="pretty-print";press(TIKEY_ENTER1);run(4000000);snapshot(argv[2],"03-pretty-print");
    phase="history-selected";press(TIKEY_UP);snapshot(argv[2],"04-history-selected");phase="history-close";press(TIKEY_ESCAPE);
    phase="tools-menu";press(TIKEY_F1);snapshot(argv[2],"05-tools-menu");phase="tools-close";press(TIKEY_ESCAPE);
    phase="catalog";press(TIKEY_CATALOG);snapshot(argv[2],"06-catalog");phase="catalog-scroll";press(TIKEY_DOWN);snapshot(argv[2],"07-catalog-selected");phase="catalog-close";press(TIKEY_ESCAPE);
    phase="integral";press(TIKEY_CLEAR);press(TIKEY_F3);press(TIKEY_DOWN);press(TIKEY_ENTER1);text("x^2,x,0,1)");snapshot(argv[2],"08-integral-input");phase="integral-pretty";press(TIKEY_ENTER1);run(4000000);snapshot(argv[2],"09-integral-pretty");
    phase="exponential-input";press(TIKEY_CLEAR);press(TIKEY_DIAMOND);press(TIKEY_X);text("x)");snapshot(argv[2],"10-exponential-input");
    phase="exponential-pretty";press(TIKEY_ENTER1);run(4000000);snapshot(argv[2],"11-exponential-pretty");
    phase="derivative-input";press(TIKEY_CLEAR);press(TIKEY_F3);press(TIKEY_ENTER1);text("x^3,x)");snapshot(argv[2],"12-derivative-input");
    phase="derivative-pretty";press(TIKEY_ENTER1);run(4000000);snapshot(argv[2],"13-derivative-pretty");
    phase="tall-integral-input";press(TIKEY_CLEAR);press(TIKEY_F3);press(TIKEY_DOWN);press(TIKEY_ENTER1);text("1/(1+x^2),x,0,1)");snapshot(argv[2],"14-tall-integral-input");
    phase="tall-integral-pretty";press(TIKEY_ENTER1);run(4000000);snapshot(argv[2],"15-tall-integral-pretty");
    phase="tall-integral-selected";press(TIKEY_UP);press(TIKEY_UP);snapshot(argv[2],"15b-tall-integral-selected");press(TIKEY_ESCAPE);
    phase="clipped-math-input";press(TIKEY_CLEAR);press(TIKEY_F3);press(TIKEY_DOWN);press(TIKEY_ENTER1);
    text("1/(1/(1/(1/(1/(1/(1+x^2)))))),x,0,1)");snapshot(argv[2],"15c-clipped-math-input");
    phase="clipped-math-pretty";press(TIKEY_ENTER1);run(4000000);snapshot(argv[2],"15d-clipped-math-pretty");if(retained)check_clipped_capture();
    phase="clipped-math-selected";press(TIKEY_UP);press(TIKEY_UP);snapshot(argv[2],"15e-clipped-math-selected");press(TIKEY_ESCAPE);
    phase="catalog-e";press(TIKEY_CATALOG);press(TIKEY_DIVIDE);snapshot(argv[2],"16-catalog-e");press(TIKEY_ESCAPE);snapshot(argv[2],"16b-menu-restored");
    phase="catalog-p";press(TIKEY_CATALOG);press(TIKEY_MINUS);snapshot(argv[2],"16c-catalog-p");press(TIKEY_ESCAPE);
    phase="inverse-trig-input";press(TIKEY_CLEAR);press(TIKEY_DIAMOND);press(TIKEY_Z);text("x)");snapshot(argv[2],"16d-inverse-trig-input");
    phase="inverse-trig-pretty";press(TIKEY_ENTER1);run(4000000);snapshot(argv[2],"16e-inverse-trig-pretty");
    phase="inverse-trig-selected";press(TIKEY_UP);press(TIKEY_UP);snapshot(argv[2],"16f-inverse-trig-selected");press(TIKEY_ESCAPE);
    phase="apps-menu";press(TIKEY_APPS);snapshot(argv[2],"17-apps-menu");
#ifdef GRAPH89_DRAW_TRACE
    graph89_instruction_trace=NULL;
#endif
    if(retained) {
#ifdef GRAPH89_DRAW_TRACE
        if(mid_draw_probes<10){fprintf(stderr,"Missing mid-drawing sampling coverage\n");return 1;}
        printf("%u frame validations during unfinished shape cap drawing passed\n",mid_draw_probes);
#endif
        uint8_t pixels[16000];graph89_copy_screen(pixels);int32_t cells[1024*12];
        int n=graph89_copy_retained_text(pixels,cells,1024);
        if(n>0){
            int32_t first[12];memcpy(first,cells,sizeof first);int32_t *c=first;uint8_t inverse[16000];memcpy(inverse,pixels,sizeof pixels);
            for(int y=c[1];y<c[1]+c[6];y++)for(int x=c[0];x<c[0]+c[5];x++)inverse[y*160+x]=inverse[y*160+x]==30?210:30;
            int m=graph89_copy_retained_text(inverse,cells,1024),found=0;
            for(int i=0;i<m;i++)if(cells[i*12]==c[0] && cells[i*12+1]==c[1] && cells[i*12+4]==(c[4]^1))found=1;
            if(!found){fprintf(stderr,"Inversion tracking failed\n");return 1;}
        }
        uint8_t blank[16000];memset(blank,210,sizeof blank);
        if(graph89_copy_retained_text(blank,cells,1024)!=0){fprintf(stderr,"Clear invalidation failed\n");return 1;}
        char state[4096];snprintf(state,sizeof(state),"%s/roundtrip.state",argv[2]);
        if(graph89_save(state) || graph89_restore(state) || graph89_copy_retained_text(pixels,cells,1024)!=0){fprintf(stderr,"State restoration invalidation failed\n");return 1;}
    }
    fclose(events);
    snprintf(path,sizeof(path),"%s/timing.json",argv[2]);FILE *f=fopen(path,"wb");if(!f)return 1;
    fprintf(f,"{\"host_cpu_seconds\":%.6f,\"observed_instructions\":%llu,\"events\":%llu}\n",(double)(clock()-start)/CLOCKS_PER_SEC,instruction,sequence);fclose(f);
    printf("TI-89 Titanium AMS %s: %llu events, %.3f host CPU seconds\n",tihw.rom_version,sequence,(double)(clock()-start)/CLOCKS_PER_SEC);
    graph89_stop();return 0;
}
