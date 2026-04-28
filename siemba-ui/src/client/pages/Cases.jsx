export default function Cases() {
  return (
    <div style={{ display:'flex', flexDirection:'column', gap:12 }}>
      <div style={{ display:'flex', alignItems:'center', justifyContent:'space-between' }}>
        <div>
          <div style={{ fontWeight:700, fontSize:16, color:'var(--text)' }}>Case Management</div>
          <div style={{ fontFamily:'var(--mono)', fontSize:11, color:'var(--text2)', marginTop:2 }}>
            Powered by TheHive 5 — full SOC case management, observables, and workflows
          </div>
        </div>
        <a href="/cases" target="_blank" rel="noopener noreferrer" className="btn-primary"
          style={{ padding:'7px 16px', display:'inline-block' }}>
          Open TheHive ↗
        </a>
      </div>

      <div className="card" style={{ padding:0, overflow:'hidden' }}>
        <iframe
          src="/cases/"
          title="TheHive Case Management"
          style={{ width:'100%', height:'calc(100vh - 160px)', border:'none', display:'block', background:'var(--navy)' }}
        />
      </div>
    </div>
  )
}
