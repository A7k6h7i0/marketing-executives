import urllib.request, json, ssl
ctx = ssl.create_default_context()
# login as admin
req = urllib.request.Request(
  "https://sales.digitalleadpro.com/api/v1/auth/login",
  data=json.dumps({"email":"rajesh.kumar@addphonebook.com","password":"Admin@2026","org_slug":"addphonebook"}).encode(),
  headers={"Content-Type":"application/json"},
  method="POST",
)
try:
  with urllib.request.urlopen(req, context=ctx, timeout=20) as r:
    body = json.loads(r.read().decode())
    token = body.get("data",{}).get("access_token") or body.get("access_token")
    print("login", r.status, "token", bool(token))
except Exception as e:
  print("login fail", e)
  token=None
if token:
  # GET users sample
  ureq = urllib.request.Request("https://sales.digitalleadpro.com/api/v1/users", headers={"Authorization":"Bearer "+token,"Accept":"application/json"})
  with urllib.request.urlopen(ureq, context=ctx, timeout=20) as r:
    data = json.loads(r.read().decode())
    print("users status", r.status)
    users = data.get("data") if isinstance(data.get("data"), list) else (data.get("data",{}) or {}).get("users") or data.get("users") or []
    if isinstance(data.get("data"), dict) and not users:
      users = data["data"].get("users") or data["data"].get("data") or []
    print("count", len(users) if isinstance(users, list) else type(users))
    if isinstance(users, list) and users:
      u = users[0]
      print("keys", sorted(u.keys()))
      print("sample", json.dumps({k:u.get(k) for k in list(u.keys())[:25]}, default=str)[:800])
    # try PATCH delete options
    if isinstance(users, list) and users:
      uid = users[0].get("id")
      for method, path in [("OPTIONS", f"/api/v1/users/{uid}"), ("GET", f"/api/v1/users/{uid}")]:
        try:
          q = urllib.request.Request("https://sales.digitalleadpro.com"+path, headers={"Authorization":"Bearer "+token}, method=method)
          with urllib.request.urlopen(q, context=ctx, timeout=15) as r:
            print(method, path, r.status, r.headers.get("Allow"))
        except Exception as e:
          code = getattr(getattr(e, "code", None), "__str__", lambda: None)()
          if hasattr(e, "code"): print(method, path, "err", e.code)
          else: print(method, path, "err", e)
