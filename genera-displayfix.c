#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <X11/Xlib.h>

static FILE *lg(void){ static FILE*f; if(!f){f=fopen("/tmp/xshim.log","a"); setvbuf(f,0,_IOLBF,0);} return f; }

/* genera's $DISPLAY parser strips the colon and passes a bare display
   number like "3" to XOpenDisplay, which is malformed. Rewrite any
   all-digits name to ":<n>" so it resolves to the local X server. */
static const char *fixname(const char *name, char *buf, size_t n){
  if(!name || !*name) return name;
  const char *p=name; int alldigits=1;
  for(; *p; ++p) if(*p<'0'||*p>'9'){ alldigits=0; break; }
  if(alldigits){ snprintf(buf,n,":%s",name); return buf; }
  return name;
}

Display *XOpenDisplay(const char *name){
  static Display *(*real)(const char*)=0;
  if(!real) real=(Display*(*)(const char*))dlsym(RTLD_NEXT,"XOpenDisplay");
  char buf[64];
  const char *use=fixname(name,buf,sizeof buf);
  Display *d=real(use);
  fprintf(lg(),"XOpenDisplay(\"%s\"%s) = %p\n",
          name?name:"(null/env)",
          (name&&use!=name)?" -> rewritten":"", (void*)d);
  return d;
}

Window XCreateWindow(Display*dpy,Window parent,int x,int y,unsigned w,unsigned h,
                     unsigned bw,int depth,unsigned cls,Visual*vis,
                     unsigned long vmask,XSetWindowAttributes*att){
  typedef Window(*fn)(Display*,Window,int,int,unsigned,unsigned,unsigned,int,unsigned,Visual*,unsigned long,XSetWindowAttributes*);
  static fn real=0; if(!real) real=(fn)dlsym(RTLD_NEXT,"XCreateWindow");
  Window win=real(dpy,parent,x,y,w,h,bw,depth,cls,vis,vmask,att);
  fprintf(lg(),"XCreateWindow %ux%u+%d+%d -> win=0x%lx\n",w,h,x,y,win);
  return win;
}

int XMapWindow(Display*dpy,Window w){
  typedef int(*fn)(Display*,Window); static fn real=0;
  if(!real) real=(fn)dlsym(RTLD_NEXT,"XMapWindow");
  fprintf(lg(),"XMapWindow win=0x%lx\n",w);
  return real(dpy,w);
}
int XMapRaised(Display*dpy,Window w){
  typedef int(*fn)(Display*,Window); static fn real=0;
  if(!real) real=(fn)dlsym(RTLD_NEXT,"XMapRaised");
  fprintf(lg(),"XMapRaised win=0x%lx\n",w);
  return real(dpy,w);
}
int XCloseDisplay(Display*dpy){
  typedef int(*fn)(Display*); static fn real=0;
  if(!real) real=(fn)dlsym(RTLD_NEXT,"XCloseDisplay");
  fprintf(lg(),"XCloseDisplay %p\n",(void*)dpy);
  return real(dpy);
}
