import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';

@Injectable({
  providedIn: 'root'
})
export class ConfigService {
  private config: any;

  constructor(private http: HttpClient) {}

  loadConfig(): Promise<void> {
    // Determine which environment file to load
    // In production builds, we'll use env.prod.json, otherwise env.json
    const isProduction = window.location.hostname !== 'localhost';
    const configFile = isProduction ? '/assets/env.prod.json' : '/assets/env.json';
    
    return this.http.get(configFile)
      .toPromise()
      .then(config => {
        this.config = config;
        console.log('Loaded config from:', configFile, 'Config:', config);
      })
      .catch(error => {
        console.error('Failed to load config from:', configFile, error);
        // Fallback to default values
        this.config = {
          apiUrl: isProduction ? 'https://bookrec-api.azurewebsites.net' : 'http://localhost:8080'
        };
      });
  }

  get apiUrl(): string {
    return this.config?.apiUrl ?? '';
  }
}
