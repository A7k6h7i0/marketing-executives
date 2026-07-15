import { FormEvent, useEffect, useState } from 'react';
import { Download, Phone, Plus, Search, Upload } from 'lucide-react';
import { api, getStoredUser } from '../services/api';
import './telecaller.css';

type Lead = {
  id: string;
  name: string;
  phone: string;
  company?: string | null;
  status: string;
  nextFollowAt?: string | null;
  notes?: string | null;
};

type TelecallerUser = {
  id: string;
  name?: string | null;
  email: string;
};

const LEAD_STATUSES = ['NEW', 'CONTACTED', 'INTERESTED', 'FOLLOWUP', 'WON', 'LOST'] as const;

function todayLabel() {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' });
}

function toast(message: string) {
  const el = document.createElement('div');
  el.className = 'tc__toast';
  el.textContent = message;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 2600);
}

export default function TelecallerPage() {
  const user = getStoredUser();
  const canDownloadReports =
    user?.role === 'SUPER_ADMIN' ||
    user?.role === 'REGIONAL_MANAGER' ||
    user?.role === 'SALES_MANAGER';
  const canManageLeads = canDownloadReports;

  const [q, setQ] = useState('');
  const [leads, setLeads] = useState<Lead[]>([]);
  const [selected, setSelected] = useState<Lead | null>(null);
  const [showCreate, setShowCreate] = useState(false);
  const [showBulkAssign, setShowBulkAssign] = useState(false);
  const [telecallers, setTelecallers] = useState<TelecallerUser[]>([]);
  const [selectedTelecallerIds, setSelectedTelecallerIds] = useState<string[]>([]);
  const [bulkFile, setBulkFile] = useState<File | null>(null);
  const [bulkRows, setBulkRows] = useState('');
  const [bulkForm, setBulkForm] = useState({
    startDate: todayLabel(),
    endDate: todayLabel(),
    recordsPerTelecallerPerDay: '100',
    source: 'admin-upload',
  });
  const [form, setForm] = useState({
    name: '',
    phone: '',
    company: '',
    email: '',
    source: '',
    notes: '',
  });
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);

  async function fetchLeads() {
    setLoading(true);
    try {
      const { data } = await api.get('/telecaller/leads', { params: { q, pageSize: 100 } });
      setLeads(data.items || []);
    } catch (err: unknown) {
      toast(
        (err as { response?: { data?: { error?: { message?: string } } } })?.response?.data?.error
          ?.message || 'Could not load leads',
      );
    } finally {
      setLoading(false);
    }
  }

  async function fetchTelecallers() {
    try {
      const { data } = await api.get('/telecaller/users');
      setTelecallers(data.items || []);
    } catch {
      setTelecallers([]);
    }
  }

  useEffect(() => {
    fetchLeads();
  }, [q]);

  useEffect(() => {
    if (canManageLeads) fetchTelecallers();
  }, [canManageLeads]);

  function callLead(_leadId: string) {
    // Phone-dial + OEM recording upload runs on the Android telecaller app.
    toast(
      'Place calls from the Android telecaller app so recordings can upload automatically.',
    );
  }

  async function createLead(e: FormEvent) {
    e.preventDefault();
    if (!form.name.trim() || !form.phone.trim()) {
      toast('Name and phone are required');
      return;
    }
    setSaving(true);
    try {
      const { data } = await api.post('/telecaller/leads', {
        name: form.name.trim(),
        phone: form.phone.trim(),
        company: form.company.trim() || null,
        email: form.email.trim() || null,
        source: form.source.trim() || null,
        notes: form.notes.trim() || null,
        status: 'NEW',
      });
      toast('Lead created');
      setShowCreate(false);
      setSelected(data);
      setForm({ name: '', phone: '', company: '', email: '', source: '', notes: '' });
      await fetchLeads();
    } catch (err: unknown) {
      toast(
        (err as { response?: { data?: { error?: { message?: string } } } })?.response?.data?.error
          ?.message || 'Could not create lead',
      );
    } finally {
      setSaving(false);
    }
  }

  async function updateStatus(id: string, status: string) {
    try {
      const { data } = await api.patch(`/telecaller/leads/${id}`, { status });
      setSelected(data);
      toast('Lead status updated');
      await fetchLeads();
    } catch (err: unknown) {
      toast(
        (err as { response?: { data?: { error?: { message?: string } } } })?.response?.data?.error
          ?.message || 'Could not update lead status',
      );
    }
  }

  function parseBulkRows() {
    if (!selectedTelecallerIds.length) throw new Error('Select at least one telecaller');
    const lines = bulkRows
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean);
    const dataLines = lines[0]?.toLowerCase().includes('phone') ? lines.slice(1) : lines;
    const records = dataLines.map((line) => {
      const [name = '', phone = '', company = '', email = '', ...notes] =
        line.split(',').map((part) => part.trim());
      return {
        name,
        phone,
        company: company || null,
        email: email || null,
        notes: notes.join(', ').trim() || null,
      };
    });
    const invalid = records.find((record) => !record.name || !record.phone);
    if (!records.length || invalid) {
      throw new Error('Paste rows as: name, phone, company, email, notes');
    }
    return records;
  }

  async function bulkAssign(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    try {
      if (bulkFile) {
        const formData = new FormData();
        formData.append('file', bulkFile);
        formData.append('telecallerIds', selectedTelecallerIds.join(','));
        formData.append('startDate', bulkForm.startDate);
        formData.append('endDate', bulkForm.endDate);
        formData.append('recordsPerTelecallerPerDay', bulkForm.recordsPerTelecallerPerDay || '100');
        if (bulkForm.source.trim()) formData.append('source', bulkForm.source.trim());
        const { data } = await api.post('/telecaller/leads/bulk-distribute-file', formData);
        toast(
          `Assigned ${data.assigned} leads to ${data.telecallers} telecaller(s) across ${data.workingDays} working day(s)`,
        );
      } else {
        const records = parseBulkRows();
        const { data } = await api.post('/telecaller/leads/bulk-distribute', {
          telecallerIds: selectedTelecallerIds,
          startDate: bulkForm.startDate,
          endDate: bulkForm.endDate,
          recordsPerTelecallerPerDay: Number(bulkForm.recordsPerTelecallerPerDay || 100),
          source: bulkForm.source.trim() || null,
          records,
        });
        toast(
          `Assigned ${data.assigned} leads to ${data.telecallers} telecaller(s) across ${data.workingDays} working day(s)`,
        );
      }
      setShowBulkAssign(false);
      setBulkRows('');
      setBulkFile(null);
      setSelectedTelecallerIds([]);
      await fetchLeads();
    } catch (err: unknown) {
      const message =
        err instanceof Error
          ? err.message
          : (err as { response?: { data?: { error?: { message?: string } } } })?.response?.data?.error
              ?.message || 'Could not assign leads';
      toast(message);
    } finally {
      setSaving(false);
    }
  }

  async function downloadDailyReport() {
    try {
      const date = todayLabel();
      const response = await api.get('/telecaller/calls/daily-report.xlsx', {
        params: { date },
        responseType: 'blob',
      });
      const blob = new Blob([response.data], {
        type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      });
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `telecaller-calls-${date}.xlsx`;
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
      toast('Report downloaded');
    } catch {
      toast('Could not download report');
    }
  }

  return (
    <div className="tc">
      <aside className="tc__list">
        <header className="tc__list-head">
          <h2>Leads</h2>
          <div className="tc__head-actions">
            {canDownloadReports && (
              <button type="button" className="btn btn--ghost" onClick={downloadDailyReport}>
                <Download size={14} /> Report
              </button>
            )}
            {canManageLeads && (
              <button type="button" className="btn btn--secondary" onClick={() => setShowBulkAssign(true)}>
                <Upload size={14} /> Bulk assign
              </button>
            )}
            <button type="button" className="btn btn--secondary" onClick={() => setShowCreate(true)}>
              <Plus size={14} /> Add lead
            </button>
          </div>
        </header>
        <div className="tc__search">
          <div className="field">
            <span style={{ position: 'absolute', width: 1, height: 1, overflow: 'hidden' }}>Search</span>
            <div style={{ position: 'relative' }}>
              <Search size={14} style={{ position: 'absolute', left: 10, top: 12, color: '#6b7280' }} />
              <input
                className="input"
                style={{ paddingLeft: 32 }}
                placeholder="Search by name, phone, company"
                value={q}
                onChange={(e) => setQ(e.target.value)}
              />
            </div>
          </div>
        </div>
        <ul>
          {loading && !leads.length && <li className="tc__empty">Loading leads…</li>}
          {leads.map((l) => (
            <li
              key={l.id}
              className={selected?.id === l.id ? 'is-active' : ''}
              onClick={() => setSelected(l)}
            >
              <div className="tc__avatar">{l.name?.[0]?.toUpperCase() || '?'}</div>
              <div className="tc__lead-text">
                <div className="tc__lead-name">{l.name}</div>
                <div className="tc__lead-meta">{l.company || l.phone}</div>
              </div>
              <span className={`tc__status tc__status--${l.status.toLowerCase()}`}>{l.status}</span>
            </li>
          ))}
          {!loading && !leads.length && <li className="tc__empty">No leads. Add one to get started.</li>}
        </ul>
      </aside>

      <section className="tc__panel">
        {selected ? (
          <>
            <header className="tc__panel-head">
              <div>
                <h2>{selected.name}</h2>
                <p>
                  {selected.company} · {selected.phone}
                </p>
              </div>
              <button
                type="button"
                className="btn btn--primary"
                onClick={() => callLead(selected.id)}
              >
                <Phone size={16} /> Call via mobile app
              </button>
            </header>

            <div className="tc__details">
              <div className="tc__detail">
                <label>Status</label>
                <select
                  className="tc__status-select"
                  value={selected.status}
                  onChange={(e) => updateStatus(selected.id, e.target.value)}
                >
                  {LEAD_STATUSES.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </select>
              </div>
              <div className="tc__detail">
                <label>Next follow up</label>
                <div>{selected.nextFollowAt ? new Date(selected.nextFollowAt).toLocaleString() : '—'}</div>
              </div>
              <div className="tc__detail tc__detail--full">
                <label>Notes</label>
                <div>{selected.notes || 'No notes yet.'}</div>
              </div>
            </div>
          </>
        ) : (
          <div className="tc__empty-center">Select a lead to see details.</div>
        )}
      </section>

      {showCreate && (
        <div className="tc__modal-backdrop" onMouseDown={() => setShowCreate(false)}>
          <form className="tc__modal" onSubmit={createLead} onMouseDown={(e) => e.stopPropagation()}>
            <header className="tc__modal-head">
              <div>
                <h3>Add lead</h3>
                <p>Create a lead for this organisation&apos;s telecalling workflow.</p>
              </div>
            </header>
            <div className="tc__form-grid">
              <label className="field">
                <span>Lead name *</span>
                <input className="input" value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} autoFocus />
              </label>
              <label className="field">
                <span>Phone *</span>
                <input className="input" value={form.phone} onChange={(e) => setForm({ ...form, phone: e.target.value })} />
              </label>
              <label className="field">
                <span>Company</span>
                <input className="input" value={form.company} onChange={(e) => setForm({ ...form, company: e.target.value })} />
              </label>
              <label className="field">
                <span>Email</span>
                <input className="input" type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} />
              </label>
              <label className="field">
                <span>Source</span>
                <input className="input" value={form.source} onChange={(e) => setForm({ ...form, source: e.target.value })} />
              </label>
              <label className="tc__textarea">
                <span>Notes</span>
                <textarea value={form.notes} onChange={(e) => setForm({ ...form, notes: e.target.value })} rows={4} />
              </label>
            </div>
            <footer className="tc__modal-actions">
              <button type="button" className="btn btn--secondary" onClick={() => setShowCreate(false)}>
                Cancel
              </button>
              <button type="submit" className="btn btn--primary" disabled={saving}>
                Create lead
              </button>
            </footer>
          </form>
        </div>
      )}

      {showBulkAssign && (
        <div className="tc__modal-backdrop" onMouseDown={() => setShowBulkAssign(false)}>
          <form className="tc__modal tc__modal--wide" onSubmit={bulkAssign} onMouseDown={(e) => e.stopPropagation()}>
            <header className="tc__modal-head">
              <div>
                <h3>Bulk assign leads</h3>
                <p>Paste customer rows and distribute them date-wise to selected telecallers.</p>
              </div>
            </header>

            <div className="tc__form-grid">
              <label className="field">
                <span>Start date</span>
                <input className="input" type="date" value={bulkForm.startDate} onChange={(e) => setBulkForm({ ...bulkForm, startDate: e.target.value })} />
              </label>
              <label className="field">
                <span>End date</span>
                <input className="input" type="date" value={bulkForm.endDate} onChange={(e) => setBulkForm({ ...bulkForm, endDate: e.target.value })} />
              </label>
              <label className="field">
                <span>Records per telecaller per day</span>
                <input className="input" type="number" min={1} max={500} value={bulkForm.recordsPerTelecallerPerDay} onChange={(e) => setBulkForm({ ...bulkForm, recordsPerTelecallerPerDay: e.target.value })} />
              </label>
              <label className="field">
                <span>Source</span>
                <input className="input" value={bulkForm.source} onChange={(e) => setBulkForm({ ...bulkForm, source: e.target.value })} />
              </label>
            </div>

            <div className="tc__bulk-section">
              <div className="tc__bulk-title">Telecallers</div>
              <div className="tc__telecaller-grid">
                {telecallers.map((person) => (
                  <label key={person.id} className="tc__check">
                    <input
                      type="checkbox"
                      checked={selectedTelecallerIds.includes(person.id)}
                      onChange={() =>
                        setSelectedTelecallerIds((prev) =>
                          prev.includes(person.id) ? prev.filter((id) => id !== person.id) : [...prev, person.id],
                        )
                      }
                    />
                    <span>{person.name || person.email}</span>
                  </label>
                ))}
                {!telecallers.length && (
                  <div className="tc__helper">No TELECALLER users found. Create them from Admin first.</div>
                )}
              </div>
            </div>

            <label className="tc__file">
              <span>Excel / CSV file</span>
              <input
                type="file"
                accept=".xlsx,.xlsm,.csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,text/csv"
                onChange={(e) => setBulkFile(e.target.files?.[0] ?? null)}
              />
              <small>{bulkFile ? bulkFile.name : 'Upload .xlsx/.xlsm/.csv columns: name, phone, company, email, notes'}</small>
            </label>

            <label className="tc__textarea tc__textarea--bulk">
              <span>Customer data</span>
              <textarea
                value={bulkRows}
                onChange={(e) => setBulkRows(e.target.value)}
                rows={10}
                disabled={!!bulkFile}
                placeholder={'name, phone, company, email, notes\nRavi Kumar, 9876543210, ABC Traders, ravi@example.com, interested in demo'}
              />
            </label>
            <p className="tc__helper">
              Upload Excel/CSV or paste rows manually. The system assigns up to 100 records per selected telecaller for each working day.
            </p>

            <footer className="tc__modal-actions">
              <button type="button" className="btn btn--secondary" onClick={() => setShowBulkAssign(false)}>
                Cancel
              </button>
              <button type="submit" className="btn btn--primary" disabled={saving}>
                Assign leads
              </button>
            </footer>
          </form>
        </div>
      )}
    </div>
  );
}
