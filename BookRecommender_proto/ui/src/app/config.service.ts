import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { firstValueFrom } from 'rxjs';

export interface AppConfig {
  apiUrl: string;
  environment: string;
}

@Injectable({
  providedIn: 'root'
})
export class ConfigService {
  private config: AppConfig | null = null;

  constructor(private http: HttpClient) {}

  async loadConfig(): Promise<AppConfig> {
    if (this.config) {
      return this.config;
    }

    try {
      this.config = await firstValueFrom(
        this.http.get<AppConfig>('/config.json')
      );
      return this.config;
    } catch (error) {
      console.error('Failed to load config.json, using defaults:', error);
      // Fallback configuration
      this.config = {
        apiUrl: 'http://localhost:5206',
        environment: 'development'
      };
      return this.config;
    }
  }

  getApiUrl(): string {
    return this.config?.apiUrl || 'http://localhost:5206';
  }
}
