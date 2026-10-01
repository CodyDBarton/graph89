#include "Graph89Core.h"
#include "ti68k_def.h"
#include "keydefs.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void press(int key) {
    graph89_key(key,1);
    for(int i=0;i<8;i++) graph89_run(50000);
    graph89_key(key,0);
    for(int i=0;i<8;i++) graph89_run(50000);
}
int main(int argc, char **argv) {
    if (argc != 4 && argc != 5) { fprintf(stderr,"Usage: boot-test OS.89u image.img screen.pgm [state-file]\n"); return 2; }
    int error=graph89_start(argv[1],argv[2]);
    if(error) { fprintf(stderr,"Boot error: %d\n",error); return 1; }
    for(int i=0;i<600;i++) graph89_run(50000);
    uint8_t pixels[16000];
    if(argc==5 && strcmp(argv[4],"--expected-five")) {
        error=graph89_restore(argv[4]);
        if(error) { fprintf(stderr,"Restore error: %d\n",error); return 1; }
    } else {
        press(TIKEY_HOME); press(TIKEY_CLEAR);
        press(argc==5 ? TIKEY_2 : TIKEY_1); press(TIKEY_PLUS); press(argc==5 ? TIKEY_3 : TIKEY_1); press(TIKEY_ENTER1);
        graph89_copy_screen(pixels);
        char state[4096]; snprintf(state,sizeof state,"%s.state",argv[2]);
        error=graph89_save(state);
        if(error) { fprintf(stderr,"Save error: %d\n",error); return 1; }
        press(TIKEY_CLEAR); press(TIKEY_9);
        error=graph89_restore(state);
        uint8_t restored[16000]; graph89_copy_screen(restored);
        if(error || memcmp(pixels,restored,sizeof pixels)) {
            fprintf(stderr,"Saved-state round trip failed (%d)\n",error); return 1;
        }
        printf("Entered %s; saved-state screen restored exactly\n", argc==5 ? "2+3" : "1+1");
    }
    graph89_copy_screen(pixels);
    FILE *f=fopen(argv[3],"wb"); if(!f) return 2;
    fprintf(f,"P5\n160 100\n255\n"); fwrite(pixels,1,sizeof pixels,f); fclose(f);
    printf("Booted model %d, OS %s, LCD on %d, RAM %u, ROM %u\n",tihw.calc_type,tihw.rom_version,tihw.on_off,tihw.ram_size,tihw.rom_size);
    graph89_stop(); return 0;
}
