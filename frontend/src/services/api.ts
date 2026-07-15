import axios from 'axios';

const TOKEN_KEY = 'me_token';
const USER_KEY = 'me_user';

export const API_BASE_URL = 'https://sales.digitalleadpro.com/api/v1';

export const api = axios.create({
  baseURL: API_BASE_URL,
  headers: { 'Content-Type': 'application/json' },
});

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
  org_id?: string | null;
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
  const { data } = await api.post('/auth/login', { email, password });
  const payload = data?.data ?? data;
  const token = payload?.access_token ?? payload?.token;
  const user = payload?.user as AuthUser;

  if (!token || !user) {
    throw new Error(data?.error?.message ?? 'Login failed');
  }

  localStorage.setItem(TOKEN_KEY, token);
  localStorage.setItem(USER_KEY, JSON.stringify(user));
  return user;
}

export function logout() {
  clearAuth();
}
