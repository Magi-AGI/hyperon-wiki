import json, re, sys

KEY_PARTS = {"linas vepstas", "ben goertzel", "nil geisweiller", "linasvepstas@gmail.com", "ben@goertzel.org", "ngeiswei@gmail.com", "linas@linas.org"}

def is_key(fh):
    return any(k in fh.lower() for k in KEY_PARTS)

def cfrom(fh):
    n = re.sub(r"<[^>]+>", "", fh).strip().strip('"').strip(chr(39))
    return n if n else fh

def cbody(b):
    if not b: return ""
    b = re.sub(r"https?://u\d+\.ct\.sendgrid\.net/\S+", "", b)
    b = re.sub(r"https?://groups\.google\.com/d/\S+", "", b)
    b = re.sub(r"--\s*
You received this message because.*$", "", b, flags=re.DOTALL)
    b = re.sub(r"To unsubscribe from this group.*$", "", b, flags=re.DOTALL)
    b = re.sub(r"To view this discussion on the web.*$", "", b, flags=re.DOTALL)
    b = re.sub(r"For more options, visit.*$", "", b, flags=re.DOTALL)
    b = re.sub(r"
-- 
.*$", "", b, flags=re.DOTALL)
