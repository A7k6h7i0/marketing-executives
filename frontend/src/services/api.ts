import axios from 'axios';

const TOKEN_KEY = 'me_token';
const USER_KEY = 'me_user';

export const api = axios.create({ baseURL: '' });

api.interceptors.request.use((config) => {
  const token = localStorage.getItem(TOKEN_KEY);
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

export type AuthUser = {
  id: string;
  email: string;
  phone?: string | null;
  role: string;
  region?: string | null;
};

export function getStoredUser(): AuthUser | null {
  const raw = localStorage.getItem(USER_KEY);
  return raw ? (JSON.parse(raw) as AuthUser) : null;
}

export function clearAuth() {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}

export async function login(email: string, password: string) {
  const { data } = await api.post('/auth/login', {
    email,
    password,
    deviceId: 'web-telecaller-panel',
  });
  localStorage.setItem(TOKEN_KEY, data.token);
  localStorage.setItem(USER_KEY, JSON.stringify(data.user));
  return data.user as AuthUser;
}

export function logout() {
  clearAuth();
}
