#!/usr/bin/env python3
"""Verify all graph modes using fresh ROM-backed calculator sessions."""
from pathlib import Path
import argparse,subprocess,math
ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('rom',type=Path);p.add_argument('--output',type=Path,default=ROOT/'build/plot-modes');p.add_argument('--reuse',action='store_true',help='Reuse completed captures when only updating assertions');a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=True)
with (out/'build.log').open('a' if a.reuse else 'w') as f:
 if not a.reuse:subprocess.run(['python3',str(ROOT/'ios/tools/build_native.py'),'--sdk','macosx','--draw-trace'],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT,check=True)
j=ROOT/'app/src/main/jni';d=ROOT/'ios/build/macosx-draw-trace'
incs=[d/'include',ROOT/'ios/native',j/'glib',j/'glib/glib',j/'tiemu-3.03/src']+[j/x/'src' for x in ['libticonv-1.1.3','libtifiles2-1.1.5','libticables2-1.3.3','libticalcs2-1.1.7']]+[j/'tiemu-3.03/src'/x for x in ['core','core/uae','core/ti_hw','core/ti_sw','core/dbg','misc','gui']]
cmd=['xcrun','clang','-std=gnu99','-O2','-DHAVE_CONFIG_H','-DNO_GDB','-DNO_SOUND','-DGRAPH89_DRAW_TRACE','-Wl,-dead_strip']
for i in incs:cmd+=['-I',str(i)]
exe=out/'modes';cmd+=[str(ROOT/'tools/plot-trace/modes.c'),str(d/'libGraph89.a'),'-lz','-liconv','-o',str(exe)];
if not a.reuse:subprocess.run(cmd,check=True)
for mode in range(1,7):
 for hd in [0,8]:
  folder=out/f'mode-{mode}-{hd}';folder.mkdir(exist_ok=True)
  with (folder/'run.log').open('a' if a.reuse else 'w') as f:
   if not (a.reuse and (folder/'graph.pgm').exists()):subprocess.run([str(exe),str(a.rom.resolve()),str(mode),str(hd),str(folder)],stdout=f,stderr=subprocess.STDOUT,check=True)
  print(mode,hd,'captured',flush=True)

def rows(folder, name, kind):
 return [list(map(float,line.split())) for line in (folder/f'{name}.{kind}').read_text().splitlines()]
def window(folder,name='graph'):
 return [float(line) for line in (folder/f'{name}.window').read_text().splitlines()]
def world(folder):
 w=window(folder)
 return [(w[0]+x/158*(w[1]-w[0]),w[4]-(y-16)/76*(w[4]-w[3])) for x,y in rows(folder,'graph','points')[2:] if math.isfinite(x)]
for mode in range(1,7):
 hd=out/f'mode-{mode}-8';original=out/f'mode-{mode}-0'
 assert len(rows(hd,'graph','points'))>3, ('Missing HD mode',mode)
 for kind in ['points','geometry','background.pgm']:
  assert (hd/f'graph.{kind}').read_bytes()==(hd/f'restored.{kind}').read_bytes(),('Save/restore',mode,kind)
 for name in ['right','left','trace','held','menu','closed']:
  assert len(rows(hd,name,'points'))>3,('Navigation lost HD',mode,name)
 assert window(hd)==window(original),('Temporary density setting was not restored',mode)
 assert window(hd,'editor')==window(original,'editor'),('Opening an editor changed density',mode)
 if mode<=4:
  assert (hd/'graph.pgm').read_bytes()==(original/'graph.pgm').read_bytes(),('Native LCD changed',mode)
 if mode==2:
  error=max(abs(x*x+y*y-1) for x,y in world(hd));assert error<2e-5,error
 if mode==3:
  error=max(abs(x*x+y*y-4*math.cos(3*math.atan2(y,x))**2) for x,y in world(hd) if x*x+y*y>1e-4);assert error<1e-4,error
 if mode==4:
  assert all(abs(x-round(x))<1e-5 and abs(y-x*x)<1e-4 for x,y in world(hd))
  assert sum(math.isnan(d[0]) and d[1]==-6 for d in rows(hd,'graph','geometry'))==3
 if mode==5:
  mesh=rows(hd,'graph','mesh');native=rows(original,'graph','mesh')
  assert mesh[0]==[3969,7812] and native[0]==[225,420],(mesh[0],native[0])
  vertices=mesh[1:];w=window(hd)
  for x,y,z,px,py in vertices:
   wx=w[0]+(x/16384+1)/2*(w[1]-w[0]);wy=w[3]+(y/16384+1)/2*(w[4]-w[3]);wz=w[8]+(z/16384+1)/2*(w[9]-w[8])
   assert abs(wz-math.sin(wx)*math.cos(wy))<0.003,(wx,wy,wz)
  assert rows(hd,'rotated','points')!=rows(hd,'graph','points'), '3D rotation did not update projection'
  pts=rows(hd,'graph','points')[2:];edges=rows(hd,'graph','edges')
  assert len(pts)==3*len(edges)
  for index,(u,v) in enumerate(edges):
   for point,vertex in zip(pts[index*3+1:index*3+3],[vertices[int(u)],vertices[int(v)]]):
    assert abs(point[0]-vertex[3])<0.51 and abs(point[1]-16-vertex[4])<0.51,('Projection rounding',point,vertex)
 if mode==6:
  error=max(abs(y-math.exp(x))/math.exp(x) for x,y in world(hd) if y>0)
  assert error<0.0002,error
  assert len(rows(hd,'graph','points'))>2000
  geometry=rows(hd,'graph','geometry');assert len(geometry)>300
  w=window(hd);field_checks=0
  for x,y,u,v in geometry[35:]:
   if not all(math.isfinite(a) for a in [x,y,u,v]) or min(x,u)<0.01 or max(x,u)>158.99 or min(y,v)<16.01 or max(y,v)>92.99 or abs(u-x)<0.01:continue
   wy=w[4]-(((y+v)/2-0.5)-16)/76*(w[4]-w[3])
   expected=wy*(76/(w[4]-w[3]))/(158/(w[1]-w[0]))
   assert abs(-(v-y)/(u-x)-expected)<3e-5,('Slope-field direction',x,y,u,v)
   field_checks+=1
  assert field_checks>300
 print('Mode',mode,'numerical, navigation and cache checks passed',flush=True)

for mode in [2,3,5,6]:
 folder=out/f'pending-{mode}';folder.mkdir(exist_ok=True)
 with (folder/'run.log').open('a' if a.reuse else 'w') as f:
  if not (a.reuse and (folder/'graph.pgm').exists()):subprocess.run([str(exe),str(a.rom.resolve()),str(mode),'8',str(folder),'pending'],stdout=f,stderr=subprocess.STDOUT,check=True)
 assert window(folder)==window(out/f'mode-{mode}-0'),('Pending density restore',mode)
 assert len((folder/'graph.pgm').read_bytes())>=16000
 print('Mode',mode,'mid-plot save/restore passed',flush=True)
for mode in range(1,7):
 for speed in [1,3]:
  folder=out/f'scroll-{mode}-{speed}';folder.mkdir(exist_ok=True)
  with (folder/'run.log').open('a' if a.reuse else 'w') as f:
   if not (a.reuse and (folder/'graph.pgm').exists()):subprocess.run([str(exe),str(a.rom.resolve()),str(mode),'8',str(folder),f'scroll-{speed}'],stdout=f,stderr=subprocess.STDOUT,check=True)
  for name in ['home','y-down']:
   log=rows(folder,name,'hold')
   assert all(row[1]==(1 if row[0]<35 else speed) for row in log),(mode,speed,name)
 for name in ['home','y-down']:
  assert (out/f'scroll-{mode}-1'/f'{name}.hold').read_bytes()!=(out/f'scroll-{mode}-3'/f'{name}.hold').read_bytes()
 assert (out/f'scroll-{mode}-1'/'y-down.pgm').read_bytes()!=(out/f'scroll-{mode}-3'/'y-down.pgm').read_bytes(),('Editor movement',mode)
 baseline=rows(out/f'scroll-{mode}-1','home','hold');fast=rows(out/f'scroll-{mode}-3','home','hold')
 normal_distance=baseline[0][2]-baseline[-1][2];fast_distance=fast[0][2]-fast[-1][2]
 assert normal_distance>0 and 2.5<fast_distance/normal_distance<3.5,('Home cursor speed',mode,normal_distance,fast_distance)
 print('Mode',mode,'Home/editor 0.35-second holds passed',flush=True)

undefined=out/'undefined-3d';undefined.mkdir(exist_ok=True)
with (undefined/'run.log').open('w') as f:subprocess.run([str(exe),str(a.rom.resolve()),'5','8',str(undefined),'undefined'],stdout=f,stderr=subprocess.STDOUT,check=True)
assert all(window(undefined)[i]==window(out/'mode-5-0')[i] for i in [0,1,2,3,4,5,8,9]),'Undefined surface left window density overridden'
print('Undefined 3D surface restored window settings',flush=True)

for mode in [2,3,5,6]:
 for action in ['interrupt','disable']:
  folder=out/f'{action}-{mode}';folder.mkdir(exist_ok=True)
  with (folder/'run.log').open('a' if a.reuse else 'w') as f:
   if not (a.reuse and (folder/'graph.pgm').exists()):subprocess.run([str(exe),str(a.rom.resolve()),str(mode),'8',str(folder),action],stdout=f,stderr=subprocess.STDOUT,check=True)
  actual,expected=window(folder),window(out/f'mode-{mode}-0')
  for index in ([2,5] if mode==5 else [10,12,13,14] if mode==6 else [0,1,3,4]):
   assert actual[index]==expected[index],('Density after',mode,action,index,actual[index],expected[index])
  print('Mode',mode,action,'restored settings',flush=True)

for style in ['box','hidden']:
 for hd in [0,8]:
  folder=out/f'3d-{style}-{hd}';folder.mkdir(exist_ok=True)
  with (folder/'run.log').open('w') as f:subprocess.run([str(exe),str(a.rom.resolve()),'5',str(hd),str(folder),style],stdout=f,stderr=subprocess.STDOUT,check=True)
  assert window(folder)[2]==14 and window(folder)[5]==14
 if style=='hidden':
  assert not rows(out/f'3d-{style}-8','graph','points'),'Unsupported 3D style replaced'
  assert (out/f'3d-{style}-0'/'graph.pgm').read_bytes()==(out/f'3d-{style}-8'/'graph.pgm').read_bytes()
 else:
  bg=(out/f'3d-{style}-8'/'graph.background.pgm').read_bytes()[-16000:]
  assert sum(pixel==30 for pixel in bg[2560:14880])>20,'Native 3D labels lost'
  assert len(rows(out/f'3d-{style}-8','graph','geometry'))==13,'HD 3D box edges lost'
 print('3D',style,'background/fallback verified',flush=True)

# Polar Trace uses two rows, including theta above the usual coordinate line.
for name in ['trace','held']:
 folder=out/'mode-3-8';mask=(folder/f'{name}.overlay').read_bytes()
 glyphs=[list(map(int,l.split())) for l in (folder/f'{name}.packets').read_text().splitlines()]
 readouts=[g for g in glyphs if 0<=g[2]<=2 and 70<=g[1]<93]
 assert any(g[3]==136 for g in readouts),'Missing retained theta identity'
 for g in readouts:
  x,y,f,c,inv,w,h,attr,l,t,r,b=g
  assert all(mask[py*160+px]&2 for py in range(max(16,y,t),min(93,y+h,b)) for px in range(max(0,x-1,l),min(159,x+w,r))),(name,'Readout cell clipped',g)
print('Polar theta and every Trace digit retain complete text cells',flush=True)
folder=out/'clipped-3d';folder.mkdir(exist_ok=True)
with (folder/'run.log').open('w') as f:subprocess.run([str(exe),str(a.rom.resolve()),'5','8',str(folder),'clipped'],stdout=f,stderr=subprocess.STDOUT,check=True)
assert len(rows(folder,'graph','points'))>1000,'Deleted edges forced 3D raster fallback'
assert any(4294967295 in e for e in rows(folder,'graph','edges')),'Clipped fixture must include deleted edges'
assert (folder/'graph.points').read_bytes()==(folder/'restored.points').read_bytes(),'Clipped 3D cache restore'
print('Clipped 3D wireframe skips deleted edges and retains HD through restore/navigation',flush=True)

folder=out/'polar-stream';folder.mkdir(exist_ok=True)
with (folder/'run.log').open('w') as f:subprocess.run([str(exe),str(a.rom.resolve()),'3','8',str(folder),'stream'],stdout=f,stderr=subprocess.STDOUT,check=True)
packets=[list(map(int,line.split())) for line in (folder/'held.packets').read_text().splitlines()]
assert any(t[3]==136 and t[1]==76 for t in packets),'Mid-character capture discarded theta identity'
assert sum(70<=t[1]<93 for t in packets)>=20,'Mid-string capture discarded Trace digits'
print('Frequent mid-draw snapshots preserve theta and Trace digits after eight movements',flush=True)
