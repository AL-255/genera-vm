/* Make the Xephyr window borderless and move it to a monitor's origin so it
   exactly covers that monitor -> borderless "fullscreen". Works reliably on
   GNOME/mutter (which honors client moves but won't fullscreen a fixed-size
   window). Use a secondary monitor (no top bar) for a clean full cover.
   Usage: genera-fullscreen [X Y]   (default 2560 0 = DVI-I-2 origin) */
#include <X11/Xlib.h>
#include <X11/Xatom.h>
#include <X11/Xutil.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static Window find_xephyr(Display*d, Window w){
  Window root,parent,*kids; unsigned n;
  XClassHint ch;
  if(XGetClassHint(d,w,&ch)){
    int hit = (ch.res_name && strstr(ch.res_name,"Xephyr")) ||
              (ch.res_class && strstr(ch.res_class,"Xephyr"));
    if(ch.res_name)XFree(ch.res_name);
    if(ch.res_class)XFree(ch.res_class);
    if(hit) return w;
  }
  if(XQueryTree(d,w,&root,&parent,&kids,&n)){
    for(unsigned i=0;i<n;i++){ Window r=find_xephyr(d,kids[i]); if(r){if(kids)XFree(kids);return r;} }
    if(kids)XFree(kids);
  }
  return 0;
}

/* Motif hints: flags bit 1 (0x2) = decorations field present; decorations 0 = none. */
typedef struct { unsigned long flags, functions, decorations; long input_mode; unsigned long status; } MwmHints;

int main(int argc,char**argv){
  int X = argc>1?atoi(argv[1]):2560;   /* DVI-I-2 origin */
  int Y = argc>2?atoi(argv[2]):0;

  Display*d=XOpenDisplay(NULL); if(!d){fprintf(stderr,"no display\n");return 1;}
  Window root=DefaultRootWindow(d);
  Window xe=0;
  for(int t=0;t<60 && !xe;t++){ xe=find_xephyr(d,root); if(!xe) usleep(200000); }
  if(!xe){fprintf(stderr,"Xephyr window not found\n");return 1;}

  /* Remove window-manager decorations (borderless). */
  Atom mwm=XInternAtom(d,"_MOTIF_WM_HINTS",False);
  MwmHints h; memset(&h,0,sizeof h); h.flags=0x2; h.decorations=0;
  XChangeProperty(d,xe,mwm,mwm,32,PropModeReplace,(unsigned char*)&h,5);
  XFlush(d); usleep(200000);

  /* Move to the monitor origin (reassert a few times; the WM settles after map). */
  for(int i=0;i<4;i++){ XMoveWindow(d,xe,X,Y); XRaiseWindow(d,xe); XFlush(d); usleep(250000); }

  XWindowAttributes a; XGetWindowAttributes(d,xe,&a);
  printf("Xephyr 0x%lx -> borderless at +%d+%d (%dx%d)\n",xe,a.x,a.y,a.width,a.height);
  return 0;
}
