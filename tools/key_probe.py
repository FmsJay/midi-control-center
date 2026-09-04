# Logs which keyboard keys go down system-wide for 300 s (ctypes GetAsyncKeyState polling), to see what the
# Oxygen Pro types for Shift + Tempo. Diagnostic only; output key_probe.txt.
import ctypes, time
u=ctypes.windll.user32
NAMES={0x08:"Backspace",0x09:"Tab",0x0D:"Enter",0x10:"Shift",0x11:"Ctrl",0x12:"Alt",0x14:"CapsLock",0x1B:"Esc",0x20:"Space",0x21:"PgUp",0x22:"PgDn",0x23:"End",0x24:"Home",0x25:"Left",0x26:"Up",0x27:"Right",0x28:"Down",0x2D:"Ins",0x2E:"Del",0x5B:"LWin",0x5C:"RWin",0xA0:"LShift",0xA1:"RShift",0xA2:"LCtrl",0xA3:"RCtrl",0xA4:"LAlt",0xA5:"RAlt",0xBB:"=",0xBD:"-",0xBC:",",0xBE:".",0xBF:"/",0xC0:"`",0xDB:"[",0xDD:"]",0xDC:"\\",0xBA:";",0xDE:"'"}
for i in range(0x30,0x3A): NAMES[i]=chr(i)
for i in range(0x41,0x5B): NAMES[i]=chr(i)
for i in range(0x70,0x88): NAMES[i]="F%d"%(i-0x6F)
for i in range(0x60,0x6A): NAMES[i]="Num%d"%(i-0x60)
down=set(); out=open("key_probe.txt","w"); t0=time.time()
while time.time()-t0<300:
    for vk in range(1,255):
        if vk in (1,2,4): continue   # mouse buttons
        st=u.GetAsyncKeyState(vk)&0x8000
        if st and vk not in down:
            down.add(vk); out.write("%7.2f DOWN %s (0x%02X) held=%s\n"%(time.time()-t0,NAMES.get(vk,"?"),vk,",".join(NAMES.get(v,"0x%02X"%v) for v in sorted(down) if v!=vk))); out.flush()
        elif not st and vk in down:
            down.discard(vk)
    time.sleep(0.003)
out.close()
