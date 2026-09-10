'use client';
import { useEffect, useState } from 'react';

type Health = any;

export default function Dashboard() {
  const [health, setHealth] = useState<Health>(null);
  const [stats, setStats] = useState<any>(null);
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/health').then(r=>r.json()).then(setHealth).catch(e=>setErr(String(e)));
    fetch('/api/stats').then(r=>r.json()).then(setStats).catch(()=>{});
  }, []);

  const kcUrl = process.env.NEXT_PUBLIC_KEYCLOAK_URL || 'https://sso.rentoption.com';
  const realm = process.env.NEXT_PUBLIC_KEYCLOAK_REALM || 'rentoption.com';
  const loginHref = `${kcUrl}/realms/${realm}/protocol/openid-connect/auth?client_id=samba-admin-ui&response_type=code&scope=openid%20profile%20email%20roles&redirect_uri=${encodeURIComponent(typeof window!=='undefined'?window.location.origin+'/api/auth/callback/keycloak':'https://dc.rentoption.com')}`;

  return (
    <div>
      <h1 style={{ margin: 0, fontSize: 22 }}>Dashboard — MVP</h1>
      <p style={{ opacity: 0.7 }}>Samba AD DC • <code>samba:389</code> • Keycloak <code>{kcUrl}</code> • Oracle prefs/audit (samba_ui_*) • Redis queue</p>

      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px,1fr))', gap: 12, marginTop: 16 }}>
        {[
          ['LDAP', health?.ldap?.ok ? 'green' : health ? 'red' : '...'],
          ['Keycloak', health?.keycloak?.ok ? 'green' : 'yellow'],
          ['Redis', health?.redis?.ok ? 'green' : 'yellow'],
          ['Oracle', typeof health?.oracle==='string' ? 'yellow' : '...'],
        ].map(([k,v]: any)=>(
          <div key={k} style={{ border: '1px solid #222', borderRadius: 10, padding: 12, background: '#111' }}>
            <div style={{ fontSize: 11, opacity: 0.6 }}>{k}</div>
            <div style={{ fontSize: 18, color: v==='green'?'#22c55e':v==='red'?'#ef4444':'#eab308' }}>{String(v)}</div>
          </div>
        ))}
      </div>

      <div style={{ marginTop: 16, display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(160px,1fr))', gap: 12 }}>
        {stats?.counts ? Object.entries(stats.counts).map(([k,v]: any)=>(
          <div key={k} style={{ border: '1px solid #222', borderRadius: 10, padding: 12, background: '#111' }}>
            <div style={{ fontSize: 11, opacity: 0.6 }}>{k}</div>
            <div style={{ fontSize: 20 }}>{v ?? '…'}</div>
          </div>
        )) : <div style={{ opacity: 0.6 }}>Loading counts from LDAP… (null = bind not configured yet)</div>}
      </div>

      <div style={{ marginTop: 20, display: 'flex', gap: 8 }}>
        <a href={loginHref} style={{ padding: '8px 12px', background: '#2563eb', color: 'white', borderRadius: 8, textDecoration: 'none' }}>Login with Keycloak (samba-admin-ui)</a>
        <a href="/api/health" style={{ padding: '8px 12px', border: '1px solid #333', borderRadius: 8, textDecoration: 'none', color: '#e5e5e5' }}>Raw /api/health</a>
      </div>

      {err && <pre style={{ background: '#1a1a1a', padding: 12, borderRadius: 8, marginTop: 12, overflow: 'auto' }}>{err}</pre>}
      {health && <pre style={{ background: '#111', padding: 12, borderRadius: 8, marginTop: 12, overflow: 'auto', fontSize: 12 }}>{JSON.stringify(health, null, 2)}</pre>}
    </div>
  );
}
