import { Component, signal, OnInit } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { inject } from '@angular/core';
import { firstValueFrom } from 'rxjs';
import { ConfigService } from './config.service';

interface Greeting {
  id: number;
  name: string;
  createdAt: string;
}

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, FormsModule],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App implements OnInit {
  private http = inject(HttpClient);
  private configService = inject(ConfigService);
  
  protected readonly title = signal('ui');
  protected readonly nameInput = signal('');
  protected readonly greetingResponse = signal('');
  protected readonly isLoading = signal(false);
  protected readonly allNames = signal<Greeting[]>([]);
  protected readonly isLoadingNames = signal(false);
  
  private apiBaseUrl = 'http://localhost:5206'; // Default fallback
  
  async ngOnInit() {
    // Load configuration at startup
    try {
      const config = await this.configService.loadConfig();
      this.apiBaseUrl = config.apiUrl;
      console.log('Loaded API URL from config:', this.apiBaseUrl);
    } catch (error) {
      console.error('Failed to load config, using default:', error);
    }
  }
  
  async callGreetingApi() {
    this.isLoading.set(true);
    this.greetingResponse.set('');
    
    console.log('API Base URL:', this.apiBaseUrl);
    console.log('Full API URL:', `${this.apiBaseUrl}/api/greet?name=${encodeURIComponent(this.nameInput())}`);
    console.log('Current hostname:', window.location.hostname);
    console.log('Current origin:', window.location.origin);
    
    try {
      const response = await firstValueFrom(
        this.http.get<{message: string, timestamp: string}>(
          `${this.apiBaseUrl}/api/greet?name=${encodeURIComponent(this.nameInput())}`
        )
      );
      
      console.log('API response received:', response);
      this.greetingResponse.set(response.message);
    } catch (error) {
      console.error('Detailed error calling API:', {
        error,
        status: (error as HttpErrorResponse).status,
        statusText: (error as HttpErrorResponse).statusText,
        message: (error as HttpErrorResponse).message,
        url: (error as HttpErrorResponse).url,
        headers: (error as HttpErrorResponse).headers
      });
      
      let errorMessage = 'Error calling API: ';
      const httpError = error as HttpErrorResponse;
      if (httpError.status === 0) {
        errorMessage += 'Network error or CORS issue. Check browser console.';
      } else if (httpError.status >= 400 && httpError.status < 500) {
        errorMessage += `Client error (${httpError.status}): ${httpError.statusText || httpError.message}`;
      } else if (httpError.status >= 500) {
        errorMessage += `Server error (${httpError.status}): ${httpError.statusText || httpError.message}`;
      } else {
        errorMessage += httpError.message || 'Unknown error';
      }
      
      this.greetingResponse.set(errorMessage);
    } finally {
      this.isLoading.set(false);
    }
  }
  
  updateNameInput(event: Event) {
    const target = event.target as HTMLInputElement;
    this.nameInput.set(target.value);
  }
  
  async getAllNames() {
    this.isLoadingNames.set(true);
    
    console.log('Getting all names from API:', `${this.apiBaseUrl}/api/greetings`);
    
    try {
      const response = await firstValueFrom(
        this.http.get<Greeting[]>(`${this.apiBaseUrl}/api/greetings`)
      );
      
      console.log('Names API response received:', response);
      this.allNames.set(response);
    } catch (error) {
      console.error('Error getting all names:', error);
      
      let errorMessage = 'Error getting names: ';
      const httpError = error as HttpErrorResponse;
      if (httpError.status === 0) {
        errorMessage += 'Network error or CORS issue. Check browser console.';
      } else if (httpError.status >= 400 && httpError.status < 500) {
        errorMessage += `Client error (${httpError.status}): ${httpError.statusText || httpError.message}`;
      } else if (httpError.status >= 500) {
        errorMessage += `Server error (${httpError.status}): ${httpError.statusText || httpError.message}`;
      } else {
        errorMessage += httpError.message || 'Unknown error';
      }
      
      // Show error in the greeting response area for now
      this.greetingResponse.set(errorMessage);
    } finally {
      this.isLoadingNames.set(false);
    }
  }
  
  formatDate(dateString: string): string {
    try {
      const date = new Date(dateString);
      return date.toLocaleString();
    } catch {
      return dateString;
    }
  }
}
