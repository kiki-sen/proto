import { Injectable } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { BehaviorSubject, Observable, catchError, map, of, throwError } from 'rxjs';
import { AuthResponse, AuthState, LoginRequest, RegisterRequest, UserInfo } from '../models/auth.models';
import { ConfigService } from '../config.service';

@Injectable({
  providedIn: 'root'
})
export class AuthService {
  private readonly TOKEN_KEY = 'auth_token';
  private readonly USER_KEY = 'user_info';
  
  private get API_URL(): string {
    return `${this.configService.getApiUrl()}/api/auth`;
  }

  private authState = new BehaviorSubject<AuthState>({
    isLoggedIn: false,
    user: null,
    token: null
  });

  public authState$ = this.authState.asObservable();

  constructor(private http: HttpClient, private configService: ConfigService) {
    this.loadStoredAuth();
  }

  private loadStoredAuth(): void {
    const token = localStorage.getItem(this.TOKEN_KEY);
    const userStr = localStorage.getItem(this.USER_KEY);
    
    if (token && userStr) {
      try {
        const user = JSON.parse(userStr) as UserInfo;
        this.authState.next({
          isLoggedIn: true,
          user,
          token
        });
      } catch {
        this.clearStoredAuth();
      }
    }
  }

  private clearStoredAuth(): void {
    localStorage.removeItem(this.TOKEN_KEY);
    localStorage.removeItem(this.USER_KEY);
    this.authState.next({
      isLoggedIn: false,
      user: null,
      token: null
    });
  }

  private storeAuth(authResponse: AuthResponse): void {
    const user: UserInfo = {
      id: authResponse.id,
      email: authResponse.email,
      createdAt: new Date().toISOString()
    };

    localStorage.setItem(this.TOKEN_KEY, authResponse.token);
    localStorage.setItem(this.USER_KEY, JSON.stringify(user));
    
    this.authState.next({
      isLoggedIn: true,
      user,
      token: authResponse.token
    });
  }

  register(registerData: RegisterRequest): Observable<AuthResponse> {
    return this.http.post<AuthResponse>(`${this.API_URL}/register`, registerData)
      .pipe(
        map(response => {
          this.storeAuth(response);
          return response;
        }),
        catchError(error => {
          console.error('Registration failed:', error);
          return throwError(() => error);
        })
      );
  }

  login(loginData: LoginRequest): Observable<AuthResponse> {
    return this.http.post<AuthResponse>(`${this.API_URL}/login`, loginData)
      .pipe(
        map(response => {
          this.storeAuth(response);
          return response;
        }),
        catchError(error => {
          console.error('Login failed:', error);
          return throwError(() => error);
        })
      );
  }

  logout(): void {
    this.clearStoredAuth();
  }

  getCurrentUser(): Observable<UserInfo> {
    const token = this.authState.value.token;
    if (!token) {
      return throwError(() => new Error('Not authenticated'));
    }

    const headers = new HttpHeaders().set('Authorization', `Bearer ${token}`);
    
    return this.http.get<UserInfo>(`${this.API_URL}/me`, { headers })
      .pipe(
        catchError(error => {
          if (error.status === 401) {
            this.clearStoredAuth();
          }
          return throwError(() => error);
        })
      );
  }

  isLoggedIn(): boolean {
    return this.authState.value.isLoggedIn;
  }

  getToken(): string | null {
    return this.authState.value.token;
  }

  getUser(): UserInfo | null {
    return this.authState.value.user;
  }
}
