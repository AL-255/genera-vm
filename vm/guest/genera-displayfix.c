#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <X11/Xlib.h>
static FILE*lg(void){static FILE*f;if(!f){f=fopen("/tmp/xshim.log","a");setvbuf(f,0,_IOLBF,0);}return f;}
/* genera mangles $DISPLAY (drops the colon). Force the real display from
   GENERA_REAL_DISPLAY if set; otherwise repair a bare-number name to ":N". */
static const char*fixname(const char*n,char*b,size_t s){
  if(!n||!*n)return n; const char*p=n; int dig=1;
  for(;*p;++p) if((*p<48||*p>57)&&*p!=46){dig=0;break;}
  if(dig){snprintf(b,s,":%s",n);return b;} return n;
}
Display *XOpenDisplay(const char*name){
  static Display*(*real)(const char*)=0;
  if(!real)real=(Display*(*)(const char*))dlsym(RTLD_NEXT,"XOpenDisplay");
  const char*over=getenv("GENERA_REAL_DISPLAY"); char buf[128]; const char*use;
  if(over&&*over) use=over; else use=fixname(name,buf,sizeof buf);
  Display*d=real(use);
  fprintf(lg(),"XOpenDisplay(\"%s\") -> \"%s\" = %p\n",name?name:"(null)",use?use:"(null)",(void*)d);
  return d;
}
