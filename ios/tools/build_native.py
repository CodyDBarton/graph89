#!/usr/bin/env python3
"""Build the bundled Graph89 C libraries for arm64 macOS, iOS, or Simulator."""
import argparse
import concurrent.futures
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
JNI = ROOT / 'app/src/main/jni'
parser = argparse.ArgumentParser()
parser.add_argument('--sdk', choices=['macosx', 'iphoneos', 'iphonesimulator'], default='macosx')
parser.add_argument('--sanitize', action='store_true')
parser.add_argument('--draw-trace', action='store_true', help='Enable the diagnostic instruction observer (no effect in normal builds)')
args = parser.parse_args()
out = ROOT / 'ios/build' / (args.sdk + ('-asan' if args.sanitize else '') + ('-draw-trace' if args.draw_trace else ''))
out.mkdir(parents=True, exist_ok=True)
overlay = out / 'include'
overlay.mkdir(exist_ok=True)

def rewrite(name, content):
    p = overlay / name
    if not p.exists() or p.read_text() != content:
        p.write_text(content)

config = (JNI / 'glib/android/config.h').read_text()
for macro in ['SIZEOF_LONG','SIZEOF_SIZE_T','SIZEOF_VOID_P','GLIB_SIZEOF_SYSTEM_THREAD']:
    config = re.sub(r'(#define '+macro+r') \d+', r'\1 8', config)
for macro in ['HAVE_MEMALIGN','HAVE_ON_EXIT','HAVE_VALUES_H','BUILD_WITH_ANDROID']:
    config = re.sub(r'^#define '+macro+r'.*$', '', config, flags=re.M)
config += '\n#define HAVE_LANGINFO_H 1\n#define HAVE_LANGINFO_CODESET 1\n#define HAVE_LOCALE_H 1\n#define HAVE_LONG_LONG_FORMAT 1\n'
rewrite('config.h', config)
glibconfig = (JNI / 'glib/android/glibconfig.h').read_text()
for macro in ['GLIB_SIZEOF_VOID_P','GLIB_SIZEOF_LONG','GLIB_SIZEOF_SIZE_T']:
    glibconfig = re.sub(r'(#define '+macro+r')\s+4', r'\1 8', glibconfig)
glibconfig = glibconfig.replace('typedef signed int gssize;', 'typedef signed long gssize;').replace('typedef unsigned int gsize;', 'typedef unsigned long gsize;')
glibconfig = glibconfig.replace('G_GSIZE_MODIFIER ""','G_GSIZE_MODIFIER "l"').replace('G_GSSIZE_FORMAT "i"','G_GSSIZE_FORMAT "li"').replace('G_GSIZE_FORMAT "u"','G_GSIZE_FORMAT "lu"').replace('G_MAXSIZE\tG_MAXUINT','G_MAXSIZE\tG_MAXULONG')
glibconfig = glibconfig.replace('(p))','(glong)(p))').replace('(i))','(glong)(i))')
for macro in ['GLONG_TO_LE','GLONG_TO_BE','GULONG_TO_LE','GULONG_TO_BE']:
    glibconfig = re.sub(r'(#define '+macro+r'.*)32', r'\g<1>64', glibconfig)
glibconfig = glibconfig.replace('char   data[4]', 'char   data[8]').replace('G_MODULE_SUFFIX "so"','G_MODULE_SUFFIX "dylib"')
rewrite('glibconfig.h',glibconfig)

modules=['glib/glib','glib/gthread','libticonv-1.1.3','libtifiles2-1.1.5','libticables2-1.3.3','libticalcs2-1.1.7','tiemu-3.03']
sources=[]
for module in modules:
    directory = JNI / module
    mk = (directory / 'Android.mk').read_text()
    match = re.search(r'LOCAL_SRC_FILES\s*:?=\s*(.*?)(?:\n\s*\n|\nLOCAL_)',mk,re.S)
    for item in match.group(1).replace('\\',' ').split():
        source = (directory / item).resolve()
        if source.name in ['gspawn.c','gbacktrace.c']:
            continue
        sources.append(source)
sources += [ROOT / 'ios/native/Graph89Core.c']
includes=[overlay, JNI/'glib',JNI/'glib/glib',JNI/'glib/glib/libcharset',JNI/'glib/glib/gnulib',JNI/'glib/glib/pcre',JNI/'glib/gthread']
includes += [JNI/m/'src' for m in modules[2:]]
includes += [JNI/'tiemu-3.03/src'/m for m in ['core','core/uae','core/ti_hw','core/ti_sw','core/dbg','misc','gui']]
includes += [ROOT/'ios/native']
cc = subprocess.check_output(['xcrun','--sdk',args.sdk,'--find','clang'],text=True).strip()
sdk = subprocess.check_output(['xcrun','--sdk',args.sdk,'--show-sdk-path'],text=True).strip()
flags=['-isysroot',sdk,'-arch','arm64','-std=gnu99','-O2','-g','-fcommon','-fno-strict-aliasing','-Wno-deprecated-declarations','-Wno-incompatible-pointer-types','-Wno-int-conversion','-Wno-format','-Wno-pointer-to-int-cast','-Wno-int-to-pointer-cast','-Wno-typedef-redefinition','-Wno-macro-redefined','-Wno-incompatible-function-pointer-types','-DDISABLE_VISIBILITY','-DHAVE_CONFIG_H','-DDEBUGGER','-DNO_GDB','-DNO_SOUND','-DSTDC','-DGLIB_COMPILATION','-DTICONV_EXPORTS','-DNO_CABLE_BLK','-DNO_CABLE_GRY','-DNO_CABLE_PAR','-DNO_CABLE_SLV','-DNO_CABLE_VTI','-DNO_CABLE_TIE','-DLIBDIR=""','-DGLIB_LOCALE_DIR=""']
if args.draw_trace: flags += ['-DGRAPH89_DRAW_TRACE']
if args.sanitize: flags += ['-fsanitize=address','-fno-omit-frame-pointer']
if args.sdk == 'iphoneos': flags += ['-miphoneos-version-min=16.0']
elif args.sdk == 'iphonesimulator': flags += ['-mios-simulator-version-min=16.0']
for inc in includes: flags += ['-I',str(inc)]
header_time=max(p.stat().st_mtime for p in JNI.rglob('*.h'))
header_time=max(header_time,*(p.stat().st_mtime for p in overlay.glob('*.h')),*(p.stat().st_mtime for p in (ROOT/'ios/native').glob('*.h')),Path(__file__).stat().st_mtime)

def compile_one(source):
    obj=out / (hashlib.sha256(str(source).encode()).hexdigest()[:12] + '.o')
    if obj.exists() and obj.stat().st_mtime > max(source.stat().st_mtime,header_time): return obj
    result=subprocess.run([cc,*flags,'-c',str(source),'-o',str(obj)],capture_output=True,text=True)
    if result.returncode:
        return source,result.stderr
    return obj

with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
    results=list(pool.map(compile_one,sources))
errors=[r for r in results if isinstance(r,tuple)]
if errors:
    for source,error in errors: print(str(source.relative_to(ROOT))+'\n'+'\n'.join(line for line in error.splitlines() if 'error:' in line),file=sys.stderr)
    print(f'{len(errors)} compilation failures; {len(sources)-len(errors)} succeeded',file=sys.stderr)
    sys.exit(1)
lib=out/'libGraph89.a'
subprocess.run(['xcrun','libtool','-static','-o',str(lib),*[str(p) for p in results]],check=True,capture_output=True)
print(lib)
if args.sdk == 'macosx':
    exe=out/'boot-test'
    subprocess.run([cc,*flags,str(ROOT/'ios/native/boot_test.c'),str(lib),'-Wl,-dead_strip','-lz','-liconv','-o',str(exe)],check=True)
    print(exe)
