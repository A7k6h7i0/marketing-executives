import { FormEvent, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { login } from '../services/api';

export default function LoginPage() {
  const navigate = useNavigate();
  const [email, setEmail] = useState('admin@alpha.com');
  const [password, setPassword] = useState('Test@1234');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  async function onSubmit(e: FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      await login(email, password);
      navigate('/telecaller');
    } catch (err: unknown) {
      const axiosErr = err as { response?: { data?: { error?: { message?: string } | string } } };
      const message =
        axiosErr.response?.data?.error &&
        typeof axiosErr.response.data.error === 'object'
          ? axiosErr.response.data.error.message
          : axiosErr.response?.data?.error || 'Login failed';
      setError(String(message));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="login-page">
      <form className="login-card" onSubmit={onSubmit}>
        <h1>Telecaller CRM</h1>
        <p>Sign in to manage telecaller leads for Marketing Executives.</p>
        <div className="field">
          <span>Email</span>
          <input className="input" value={email} onChange={(e) => setEmail(e.target.value)} />
        </div>
        <div className="field" style={{ marginTop: 12 }}>
          <span>Password</span>
          <input
            className="input"
            type="password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
          />
        </div>
        {error && <p style={{ color: '#dc2626', fontSize: 14 }}>{error}</p>}
        <button className="btn btn--primary" style={{ width: '100%', marginTop: 16 }} disabled={loading}>
          {loading ? 'Signing in…' : 'Sign in'}
        </button>
      </form>
    </div>
  );
}
