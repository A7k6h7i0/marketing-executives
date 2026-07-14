import { Outlet, useNavigate } from 'react-router-dom';
import { Headphones, LogOut } from 'lucide-react';
import { getStoredUser, logout } from './services/api';

export default function App() {
  const user = getStoredUser();
  const navigate = useNavigate();

  return (
    <div className="app-shell">
      <header className="topbar">
        <div className="topbar__brand">
          <Headphones size={18} />
          <span>Marketing Executives</span>
        </div>
        <div className="topbar__meta">
          <span>{user?.email}</span>
          <button
            type="button"
            className="btn btn--ghost"
            onClick={() => {
              logout();
              navigate('/login');
            }}
          >
            <LogOut size={14} /> Logout
          </button>
        </div>
      </header>
      <main className="app-main">
        <Outlet />
      </main>
    </div>
  );
}
