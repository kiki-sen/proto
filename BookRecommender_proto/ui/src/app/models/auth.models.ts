export interface LoginRequest {
  email: string;
  password: string;
}

export interface RegisterRequest {
  email: string;
  password: string;
  confirmPassword: string;
}

export interface AuthResponse {
  id: number;
  email: string;
  token: string;
  expires: string;
}

export interface UserInfo {
  id: number;
  email: string;
  createdAt: string;
}

export interface AuthState {
  isLoggedIn: boolean;
  user: UserInfo | null;
  token: string | null;
}
