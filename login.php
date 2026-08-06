<?php
/**
 * Exonhost NfSen login page — served by Apache mod_auth_form (form auth).
 *
 * Apache is configured (config/000-default.conf) to require a valid login for
 * every request under /var/nfsen/www. Unauthenticated requests receive an
 * HTTP 401 whose response body is this page (the "inline login" pattern):
 * the form below POSTs back to /nfsen.php, where mod_auth_form validates the
 * credentials against /var/nfsen/etc/.htpasswd and sets a session cookie.
 *
 * The login cookie is a browser-session cookie (dies when the browser
 * closes), and session-guard.php auto-logs you out after 1 hour of inactivity.
 *
 * Because this page is rendered as the 401 response, a POST request that
 * lands here means the previous login attempt was rejected (mod_auth_form
 * consumes the POST body before this page renders, so we detect the attempt
 * by the preserved request method rather than by form fields). A POST can
 * also arrive when a session expired mid-use, so the message below covers
 * both cases.
 */
$login_failed = (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') || isset($_GET['error']);
$logged_out   = isset($_GET['loggedout']);
$expired      = isset($_GET['expired']);
?><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>Sign in · Exonhost NfSen NetFlow Analyzer</title>
<style>
  :root{
    --bg:#070b18;
    --card:rgba(255,255,255,.045);
    --line:rgba(255,255,255,.09);
    --text:#e8edf7;
    --muted:#93a0b8;
    --faint:#5d6b85;
    --accent:#22d3ee;
    --accent2:#6366f1;
    --danger:#f87171;
    --ok:#34d399;
  }
  *{box-sizing:border-box;margin:0;padding:0}
  html,body{height:100%}
  body{
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
    background:
      radial-gradient(1000px 600px at 15% -10%, rgba(34,211,238,.14), transparent 60%),
      radial-gradient(900px 600px at 110% 110%, rgba(99,102,241,.18), transparent 60%),
      var(--bg);
    color:var(--text);
    display:flex;flex-direction:column;align-items:center;justify-content:center;
    min-height:100vh;padding:24px;position:relative;overflow:hidden;
  }
  /* subtle network grid */
  body::before{
    content:"";position:absolute;inset:0;pointer-events:none;
    background-image:
      linear-gradient(rgba(255,255,255,.03) 1px, transparent 1px),
      linear-gradient(90deg, rgba(255,255,255,.03) 1px, transparent 1px);
    background-size:44px 44px;
    -webkit-mask-image:radial-gradient(ellipse at 50% 40%, #000 30%, transparent 75%);
            mask-image:radial-gradient(ellipse at 50% 40%, #000 30%, transparent 75%);
  }
  .card{
    position:relative;z-index:1;width:100%;max-width:400px;
    background:var(--card);border:1px solid var(--line);border-radius:18px;
    padding:34px 32px 26px;
    backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);
    box-shadow:0 24px 60px rgba(0,0,0,.45), inset 0 1px 0 rgba(255,255,255,.05);
    animation:rise .5s cubic-bezier(.2,.8,.3,1);
  }
  @keyframes rise{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:none}}
  .brand{display:flex;flex-direction:column;align-items:center;gap:13px}
  .logo-chip{
    background:#fff;border-radius:10px;padding:11px 20px;
    box-shadow:0 12px 30px rgba(0,0,0,.35), inset 0 0 0 1px rgba(255,255,255,.6);
    display:flex;align-items:center;justify-content:center;
  }
  .logo-chip img{display:block;height:30px;width:auto;max-width:210px}
  .brand-sub{font-size:13px;color:var(--muted);letter-spacing:.3px}
  .sub{color:var(--muted);font-size:14px;line-height:1.55;margin:18px 0 20px;text-align:center}
  .banner{
    display:flex;gap:10px;align-items:flex-start;
    padding:11px 13px;border-radius:10px;font-size:13.5px;line-height:1.45;margin-bottom:18px;
  }
  .banner.error{background:rgba(248,113,113,.10);border:1px solid rgba(248,113,113,.28);color:#fecaca}
  .banner.ok{background:rgba(52,211,153,.10);border:1px solid rgba(52,211,153,.28);color:#a7f3d0}
  .banner.info{background:rgba(34,211,238,.10);border:1px solid rgba(34,211,238,.28);color:#a5f3fc}
  .banner svg{flex:none;margin-top:1px}
  form{display:grid;gap:16px}
  .field label{
    display:block;font-size:12.5px;font-weight:600;letter-spacing:.5px;
    text-transform:uppercase;color:var(--muted);margin-bottom:7px;
  }
  .input-wrap{position:relative}
  .input-wrap > svg{
    position:absolute;left:13px;top:50%;transform:translateY(-50%);
    width:17px;height:17px;color:var(--muted);pointer-events:none;
  }
  input[type=text],input[type=password]{
    width:100%;padding:12px 42px 12px 40px;
    background:rgba(255,255,255,.05);
    border:1px solid var(--line);border-radius:10px;
    color:var(--text);font-size:15px;outline:none;
    transition:border-color .18s, box-shadow .18s, background .18s;
  }
  input::placeholder{color:var(--faint)}
  input:focus{
    border-color:var(--accent);
    box-shadow:0 0 0 3px rgba(34,211,238,.18);
    background:rgba(255,255,255,.07);
  }
  .toggle{
    position:absolute;right:10px;top:50%;transform:translateY(-50%);
    background:none;border:none;color:var(--muted);cursor:pointer;
    padding:6px;border-radius:8px;display:flex;
  }
  .toggle:hover{color:var(--text);background:rgba(255,255,255,.06)}
  .toggle svg{width:18px;height:18px}
  button[type=submit]{
    margin-top:4px;padding:13px;border:none;border-radius:10px;
    font-size:15px;font-weight:700;letter-spacing:.4px;color:#04121a;cursor:pointer;
    background:linear-gradient(135deg,var(--accent),#67e8f9);
    box-shadow:0 10px 26px rgba(34,211,238,.30);
    transition:transform .15s, box-shadow .15s, filter .15s;
  }
  button[type=submit]:hover{transform:translateY(-1px);filter:brightness(1.05);box-shadow:0 14px 32px rgba(34,211,238,.4)}
  button[type=submit]:active{transform:translateY(0)}
  button[type=submit]:disabled{opacity:.6;cursor:wait;transform:none}
  .card-hint{margin-top:18px;text-align:center;font-size:12.5px;color:var(--faint);line-height:1.6}
  .page-foot{
    position:relative;z-index:1;margin-top:24px;max-width:460px;text-align:center;
    font-size:12.5px;color:var(--faint);line-height:1.8;
  }
  .page-foot strong{color:var(--muted);font-weight:600}
  .page-foot .brandline{color:var(--muted)}
  .page-foot a{color:var(--accent);text-decoration:none}
  .page-foot a:hover{text-decoration:underline}
  .page-foot .sep{opacity:.4;margin:0 6px}
</style>
</head>
<body>
  <div class="card">
    <div class="brand">
      <div class="logo-chip">
        <img src="data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAPAAAAAeCAYAAAASG5NgAAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAyFpVFh0WE1MOmNvbS5hZG9iZS54bXAAAAAAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IkFkb2JlIFhNUCBDb3JlIDUuNS1jMDE0IDc5LjE1MTQ4MSwgMjAxMy8wMy8xMy0xMjowOToxNSAgICAgICAgIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6eG1wPSJodHRwOi8vbnMuYWRvYmUuY29tL3hhcC8xLjAvIiB4bWxuczp4bXBNTT0iaHR0cDovL25zLmFkb2JlLmNvbS94YXAvMS4wL21tLyIgeG1sbnM6c3RSZWY9Imh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC9zVHlwZS9SZXNvdXJjZVJlZiMiIHhtcDpDcmVhdG9yVG9vbD0iQWRvYmUgUGhvdG9zaG9wIENDIChXaW5kb3dzKSIgeG1wTU06SW5zdGFuY2VJRD0ieG1wLmlpZDo3MjA0NzAyQUVDMEIxMUVBOERDQUI2NjlDQkM0NzhFOCIgeG1wTU06RG9jdW1lbnRJRD0ieG1wLmRpZDo3MjA0NzAyQkVDMEIxMUVBOERDQUI2NjlDQkM0NzhFOCI+IDx4bXBNTTpEZXJpdmVkRnJvbSBzdFJlZjppbnN0YW5jZUlEPSJ4bXAuaWlkOjcyMDQ3MDI4RUMwQjExRUE4RENBQjY2OUNCQzQ3OEU4IiBzdFJlZjpkb2N1bWVudElEPSJ4bXAuZGlkOjcyMDQ3MDI5RUMwQjExRUE4RENBQjY2OUNCQzQ3OEU4Ii8+IDwvcmRmOkRlc2NyaXB0aW9uPiA8L3JkZjpSREY+IDwveDp4bXBtZXRhPiA8P3hwYWNrZXQgZW5kPSJyIj8+HDRMLwAAGZlJREFUeNrsXQmYFNW1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" alt="Exonhost" width="240" height="30">
      </div>
      <p class="brand-sub">NfSen NetFlow Analyzer · Protected sign-in</p>
    </div>
    <p class="sub">Sign in to view your network flow data. Your session ends when you close the browser, or after 1 hour of inactivity.</p>

    <?php if ($logged_out): ?>
      <div class="banner ok">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>
        <span>You have been signed out.</span>
      </div>
    <?php endif; ?>

    <?php if ($expired): ?>
      <div class="banner info">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>
        <span>Your session has expired after 1 hour of inactivity. Please sign in again.</span>
      </div>
    <?php endif; ?>

    <?php if ($login_failed): ?>
      <div class="banner error">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
        <span>Invalid username or password, or your session has expired. Please sign in again.</span>
      </div>
    <?php endif; ?>

    <form method="POST" action="/nfsen.php" autocomplete="off">
      <div class="field">
        <label for="httpd_username">Username</label>
        <div class="input-wrap">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
          <input type="text" id="httpd_username" name="httpd_username" placeholder="admin" autocomplete="username" autofocus required>
        </div>
      </div>
      <div class="field">
        <label for="httpd_password">Password</label>
        <div class="input-wrap">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
          <input type="password" id="httpd_password" name="httpd_password" placeholder="••••••••" autocomplete="current-password" required>
          <button type="button" class="toggle" id="togglePass" aria-label="Show password">
            <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
          </button>
        </div>
      </div>
      <button type="submit" id="submitBtn">Sign in</button>
    </form>

    <p class="card-hint">Forgot your password? Ask the server administrator to reset it.</p>
  </div>

  <div class="page-foot">
    <p class="brandline">Powered by <strong>Exonhost</strong> — Best Domain &amp; Hosting Service Provider in Bangladesh</p>
    <p>Project created by <strong>Rezwan Abdullah</strong><span class="sep">·</span><a href="https://web.facebook.com/rezwanvaiya" target="_blank" rel="noopener">facebook.com/rezwanvaiya</a></p>
  </div>

<script>
(function(){
  var pass = document.getElementById('httpd_password');
  var btn  = document.getElementById('togglePass');
  var eyeOpen   = '<path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/>';
  var eyeClosed = '<path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/>';
  btn.addEventListener('click', function(){
    var showing = pass.type === 'text';
    pass.type = showing ? 'password' : 'text';
    btn.innerHTML = showing
      ? '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + eyeClosed + '</svg>'
      : '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' + eyeOpen + '</svg>';
  });
  var form = document.querySelector('form');
  var sb = document.getElementById('submitBtn');
  form.addEventListener('submit', function(){ sb.disabled = true; sb.textContent = 'Signing in…'; });
})();
</script>
</body>
</html>
