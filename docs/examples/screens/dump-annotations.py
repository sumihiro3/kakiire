"""`.kakiire` の注釈を、kakiire annotate -a に渡せる JSON に書き出す。使い方: python3 dump-annotations.py <file.kakiire>"""
import json, subprocess, sys
d = json.loads(subprocess.check_output(["kakiire", "info", sys.argv[1]]))
keep = ("name", "type", "geometry", "style", "text", "number", "symbol")
rows = [{k: a[k] for k in keep if k in a} for a in d["annotations"]]
print("[\n" + ",\n".join("  " + json.dumps(r, ensure_ascii=False) for r in rows) + "\n]")
