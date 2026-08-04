#!/usr/bin/env python3
"""GLM-4 powered loop-engineering: AI evaluates figures, suggests fixes, iterates."""
from PIL import Image, ImageDraw, ImageFont
import numpy as np, math, os, subprocess, json

WHITE=(255,255,255);BLACK=(20,20,20);BLUE=(20,65,150);LBLUE=(200,220,250)
ORANGE=(190,105,20);LORANGE=(250,235,215);GREEN=(22,130,45);LGREEN=(210,240,220)
RED=(185,38,38);LRED=(250,230,230);PURPLE=(115,45,155);LPURPLE=(240,230,250)
LGRAY=(240,240,240);DGRAY=(60,60,60)
FT=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',32)
FH=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',20)
FS=ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc',14)
DD=ImageDraw.Draw(Image.new('RGB',(1,1)))

def m(t,f):
    ls=t.split('\n');mw=0;th=0
    for l in ls:bb=DD.textbbox((0,0),l,font=f);tw=bb[2]-bb[0];th+=bb[3]-bb[1]+1;mw=max(mw,tw)
    return mw,th+2

def R(lt,rt,font=FS,lf=LBLUE,rf=LBLUE,ltc=DGRAY,rtc=DGRAY):
    return (lt,rt,font,lf,rf,ltc,rtc)

def build(name, rows):
    max_tw=max(m(r[0],r[2])[0] for r in rows);th=sum(m(r[0],r[2])[1] for r in rows)
    gap=4;col_w=max_tw+4;W=2*col_w+3*gap;H=th+6;r=W/H
    while r>1.75:W=int(W*0.85);col_w=(W-3*gap)//2;r=W/H
    while r<1.15:W=int(W*1.15);col_w=(W-3*gap)//2;r=W/H
    img=Image.new('RGB',(W,H),WHITE);d=ImageDraw.Draw(img);cb=[];ffs=[];y=2
    for lt,rt,font,lf,rf,ltc,rtc in rows:
        _,th2=m(lt,font) if lt.strip() else (0,22)
        if rt.strip():_,th2r=m(rt,font);th2=max(th2,th2r)
        xl=gap;d.rectangle([xl,y,xl+col_w,y+th2],fill=lf,outline=BLACK,width=2);cb.append((xl,y,col_w,th2))
        if lt.strip():
            ls=lt.split('\n');ta=sum((d.textbbox((0,0),l,font=font)[2]-d.textbbox((0,0),l,font=font)[0])*(d.textbbox((0,0),l,font=font)[3]-d.textbbox((0,0),l,font=font)[1]) for l in ls)
            ffs.append(ta/(col_w*th2)*100);ty=y+1
            for l in ls:bb=d.textbbox((0,0),l,font=font);tw=bb[2]-bb[0];d.text((xl+(col_w-tw)//2,ty),l,fill=ltc,font=font);ty+=bb[3]-bb[1]+1
        xr=2*gap+col_w;d.rectangle([xr,y,xr+col_w,y+th2],fill=rf,outline=BLACK,width=2);cb.append((xr,y,col_w,th2))
        if rt.strip():
            ls=rt.split('\n');ta=sum((d.textbbox((0,0),l,font=font)[2]-d.textbbox((0,0),l,font=font)[0])*(d.textbbox((0,0),l,font=font)[3]-d.textbbox((0,0),l,font=font)[1]) for l in ls)
            ffs.append(ta/(col_w*th2)*100);ty=y+1
            for l in ls:bb=d.textbbox((0,0),l,font=font);tw=bb[2]-bb[0];d.text((xr+(col_w-tw)//2,ty),l,fill=rtc,font=font);ty+=bb[3]-bb[1]+1
        y+=th2
    fl=[];r=W/H
    if r<1.15 or r>1.75:fl.append(f'P11_ratio={r:.2f}')
    mask=np.zeros((H,W),dtype=bool)
    for x1,y1,bw,bh in cb:x1i=max(0,int(x1));y1i=max(0,int(y1));x2i=min(W,int(x1+bw));y2i=min(H,int(y1+bh))
    if x2i>x1i and y2i>y1i:mask[y1i:y2i,x1i:x2i]=True
    bp=(W*H-np.sum(mask))/(W*H)*100
    if bp>=15.0:fl.append(f'P13_blank={bp:.1f}%')
    if ffs:mf=min(ffs)
    if mf<66.7:fl.append(f'P14_minFont={mf:.0f}%')
    png=os.path.join('.',name);img.save(png);kb=os.path.getsize(png)//1024
    ok=len(fl)==0
    print(f"  {'PASS' if ok else 'FAIL'} {name}: {W}x{H} r={W/H:.2f} blank={bp:.1f}% ({kb}KB)"+(f' {fl}' if fl else ''))
    return ok, dict(W=W,H=H,ratio=r,blank=bp,minFont=(min(ffs) if ffs else 0),failures=fl)

def ask_glm(prompt):
    """Ask GLM-4 for guidance."""
    try:
        r=subprocess.run(['ollama','run','glm4:latest',prompt],capture_output=True,text=True,timeout=60)
        return r.stdout.strip()[:500]
    except:
        return "GLM unavailable"

def glm_loop(name, rows_fn, max_iter=5):
    """GLM-4 powered iterative improvement loop."""
    for i in range(max_iter):
        rows=rows_fn(i)  # rows_fn receives iteration number
        ok,metrics=build(name, rows)
        if ok:
            print(f"\n  *** PASS after {i+1} iterations! ***")
            return True
        
        # Ask GLM-4 for fix suggestions
        prompt=f"""Figure quality check failed. Current metrics:
- P11 aspect ratio: {metrics['ratio']:.2f} (need 1.15-1.75)
- P13 blank space: {metrics['blank']:.1f}% (need <15%)
- P14 min font fill: {metrics['minFont']:.0f}% (need >=67%)
- WxH: {metrics['W']}x{metrics['H']}
- Failures: {metrics['failures']}

Suggest ONE specific change to fix the worst violation (adjust font size, add/remove rows, change W/H ratio). Reply with just the action in 1 sentence."""
        
        suggestion=ask_glm(prompt)
        print(f"  GLM-4 suggests: {suggestion[:200]}")
    return False

# Test: simple fig6 with iterative improvement
def fig6_rows(iteration):
    base_text="Post-Layout Waveforms (sky130 TT)" if iteration==0 else f"Post-Layout Simulation Waveforms (sky130 TT, Xyce 7.6, iter {iteration})"
    return [
        R(base_text,"",FT,LBLUE,LBLUE,BLUE,BLUE),
        R("(a) PLL Lock","(b) TX Burst",FH,LBLUE,LORANGE,BLUE,ORANGE),
        R("Lock:28.4us|Vctrl:0.897V|VCO:200.1MHz|Jitter:38.2ps","Freq:40kHz|8 pulses|12Vpp|UERTX:7.15uJ|Save:44.2%",FS),
        R("(c) RX Echo (wall 3m)","(d) ADC Spectrum",FH,LGREEN,LPURPLE,GREEN,PURPLE),
        R("RX:1.87mV|LNA:24.6mV|VGA:778mV|ADC:442LSB|TOF:17.49ms","SNDR:58.7dB|ENOB:9.6b|SFDR:68.2dB|FOM:117fJ",FS),
    ]

print("GLM-4 Loop-Engineering Test\n")
glm_loop('fig6_glm_test.png', fig6_rows)
print("\nDone.")
