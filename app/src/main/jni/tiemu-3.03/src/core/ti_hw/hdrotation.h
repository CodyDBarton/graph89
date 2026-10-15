/* Host projection of calculator-owned Q14 mesh geometry. */
#ifndef GRAPH89_HDROTATION_H
#define GRAPH89_HDROTATION_H
#include <math.h>
typedef struct {double row[2][3],cx,cy,sx,sy;} HDCamera;
static double hd_dot(const double *a,const double *b){return a[0]*b[0]+a[1]*b[1]+a[2]*b[2];}
static int hd_normalize(double *a){double n=sqrt(hd_dot(a,a));if(n<1e-9||!isfinite(n))return 0;for(int k=0;k<3;k++)a[k]/=n;return 1;}
static HDCamera hd_camera_mix(HDCamera a,HDCamera b,double t){
 if(t<=0)return a;if(t>=1)return b;HDCamera c;
 for(int r=0;r<2;r++)for(int k=0;k<3;k++)c.row[r][k]=a.row[r][k]+t*(b.row[r][k]-a.row[r][k]);
 if(!hd_normalize(c.row[0]))return b;
 double projection=hd_dot(c.row[0],c.row[1]);for(int k=0;k<3;k++)c.row[1][k]-=projection*c.row[0][k];
 if(!hd_normalize(c.row[1]))return b;
 c.cx=a.cx+t*(b.cx-a.cx);c.cy=a.cy+t*(b.cy-a.cy);
 c.sx=a.sx+t*(b.sx-a.sx);c.sy=a.sy+t*(b.sy-a.sy);return c;
}
static void hd_project(HDCamera c,const float *v,float *p){
 p[0]=c.cx+c.sx*(v[0]*c.row[0][0]+v[1]*c.row[0][1]+v[2]*c.row[0][2]);
 p[1]=c.cy+c.sy*(v[0]*c.row[1][0]+v[1]*c.row[1][1]+v[2]*c.row[1][2]);
}
#endif
