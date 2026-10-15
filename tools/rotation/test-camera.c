#include <assert.h>
#include <stdio.h>
#include "../../app/src/main/jni/tiemu-3.03/src/core/ti_hw/hdrotation.h"
static HDCamera camera(double angle){HDCamera c={0};double a=angle*acos(-1)/180;c.row[0][0]=cos(a);c.row[0][1]=sin(a);c.row[1][0]=-sin(a);c.row[1][1]=cos(a);c.sx=c.sy=1;return c;}
int main(void){
 HDCamera a=camera(350),b=camera(10),m=hd_camera_mix(a,b,0.5);float point[3]={1,0,0},out[2];hd_project(m,point,out);
 assert(fabs(out[0]-1)<1e-6 && fabs(out[1])<1e-6);
 for(int i=0;i<=120;i++){HDCamera c=hd_camera_mix(a,b,i/120.0);assert(fabs(hd_dot(c.row[0],c.row[1]))<1e-8);assert(fabs(hd_dot(c.row[0],c.row[0])-1)<1e-8);}
 m=hd_camera_mix(a,b,0);hd_project(m,point,out);assert(fabs(out[0]-cos(350*acos(-1)/180))<1e-6);
 puts("PASS: native endpoint projection, orthonormal intermediate cameras, and 360-degree wrap");
}
