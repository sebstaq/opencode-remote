import json, re

d = json.load(open("/tmp/ui-theme.json"))

def parse_frame(f):
    if isinstance(f, dict):
        return f["y"] + f["height"] / 2
    m = re.match(r"\{\{([^,]+), ([^}]+)\}, \{([^,]+), ([^}]+)\}\}", str(f))
    if m:
        y = float(m.group(2))
        h = float(m.group(4))
        return y + h / 2
    return None

found = None

def walk(n):
    global found
    if found is None:
        label = n.get("AXLabel") or ""
        if label.startswith("Theme tokens,"):
            found = parse_frame(n.get("AXFrame"))
            return
        for c in n.get("children") or n.get("AXChildren") or []:
            walk(c)

for t in (d if isinstance(d, list) else [d]):
    walk(t)

print(int(found) if found is not None else 225)
