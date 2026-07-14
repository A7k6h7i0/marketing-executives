import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import App from './App';
import LoginPage from './pages/LoginPage';
import TelecallerPage from './pages/TelecallerPage';
import { getStoredUser } from './services/api';
import './styles/global.css';

function Protected({ children }: { children: React.ReactNode }) {
  return getStoredUser() ? <>{children}</> : <Navigate to="/login" replace />;
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<LoginPage />} />
        <Route
          path="/telecaller"
          element={
            <Protected>
              <App />
            </Protected>
          }
        >
          <Route index element={<TelecallerPage />} />
        </Route>
        <Route path="*" element={<Navigate to="/telecaller" replace />} />
      </Routes>
    </BrowserRouter>
  </React.StrictMode>,
);
