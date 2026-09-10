export const metadata = { title: 'Samba AD — dc.rentoption.com', description: 'Internal AD Management Portal' };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body style={{ margin: 0, fontFamily: 'system-ui, sans-serif', background: '#0a0a0a', color: '#e5e5e5' }}>
        <header style={{ padding: '12px 20px', borderBottom: '1px solid #222', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <strong>Samba AD</strong> <span style={{ opacity: 0.7 }}>dc.rentoption.com — internal</span>
          <span style={{ fontSize: 12, opacity: 0.6 }}>MVP • Keycloak SSO • LDAP samba:389</span>
        </header>
        <div style={{ display: 'flex', minHeight: 'calc(100vh - 53px)' }}>
          <nav style={{ width: 220, borderRight: '1px solid #222', padding: 12 }}>
            <div style={{ fontSize: 11, opacity: 0.5, marginBottom: 8 }}>NAVIGATION</div>
            {['Dashboard','Users','Groups','OUs','DNS','Domain Health','Audit'].map(i=>(
              <div key={i} style={{ padding: '8px 10px', borderRadius: 6, background: i==='Dashboard'?'#1a1a1a':'transparent', marginBottom: 4 }}>{i}</div>
            ))}
            <div style={{ marginTop: 16, fontSize: 11, opacity: 0.5 }}>Internal only — allow 172.24/172.25/10.0</div>
            <div style={{ marginTop: 12, fontSize: 12 }}><a href="/api/health" style={{ color: '#60a5fa' }}>/api/health</a> • <a href="/api/stats" style={{ color: '#60a5fa' }}>/api/stats</a></div>
          </nav>
          <main style={{ flex: 1, padding: 20 }}>{children}</main>
        </div>
      </body>
    </html>
  );
}
