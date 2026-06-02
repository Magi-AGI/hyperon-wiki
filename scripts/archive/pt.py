import json,re,sys

KP={"linas vepstas","ben goertzel","nil geisweiller","linasvepstas@gmail.com","ben@goertzel.org","ngeiswei@gmail.com","linas@linas.org"}
def isk(fh): return any(k in fh.lower() for k in KP)
def cfr(fh):
    n=re.sub(r"<[^>]+>","",fh).strip().strip('"').strip(chr(39))
    return n if n else fh
def cb(b):
    if not b: return ""
    b=re.sub(r"https?://u\d+\.ct\.sendgrid\.net/\S+","",b)
    b=re.sub(r"https?://groups\.google\.com/d/\S+","",b)
    b=re.sub(r"--\s*
You received this message because.*$","",b,flags=re.DOTALL)
    b=re.sub(r"To unsubscribe from this group.*$","",b,flags=re.DOTALL)
    b=re.sub(r"To view this discussion.*$","",b,flags=re.DOTALL)
    b=re.sub(r"For more options, visit.*$","",b,flags=re.DOTALL)
    b=re.sub(r"
-- 
.*$","",b,flags=re.DOTALL)
    ls=b.split(chr(10));cl=[];qb=0
    for l in ls:
        if l.strip().startswith(">"):
            qb+=1
            if qb==1: cl.append("[...]")
        elif re.match(r"^On .+ wrote:$",l.strip()): pass
        elif re.match(r"^On .+,.+ wrote:$",l.strip()): pass
        else: qb=0;cl.append(l)
    b=chr(10).join(cl);b=re.sub(r"
{3,}",chr(10)+chr(10),b)
    b=re.sub(r"\[\.\.\.\](\s*\[\.\.\.\])+","[...]",b)
    return b.strip()
