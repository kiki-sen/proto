import { Component, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { HttpClient } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { inject } from '@angular/core';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet, FormsModule],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App {
  private http = inject(HttpClient);
  
  protected readonly title = signal('ui');
  protected readonly nameInput = signal('');
  protected readonly greetingResponse = signal('');
  protected readonly isLoading = signal(false);
  
  // Environment-aware API base URL
  private readonly apiBaseUrl = this.getApiBaseUrl();
  
  async callGreetingApi() {
    this.isLoading.set(true);
    this.greetingResponse.set('');
    
    console.log('API Base URL:', this.apiBaseUrl);
    console.log('Full API URL:', `${this.apiBaseUrl}/api/greet?name=${encodeURIComponent(this.nameInput())}`);
    console.log('Current hostname:', window.location.hostname);
    
    try {
      const response = await this.http.get<{message: string, timestamp: string}>(
        `${this.apiBaseUrl}/api/greet?name=${encodeURIComponent(this.nameInput())}`
      ).toPromise();
      
      if (response) {
        this.greetingResponse.set(response.message);
      }
    } catch (error) {
      console.error('Error calling API:', error);
      const errorMessage = window.location.hostname === 'localhost' 
        ? 'Error calling API. Make sure the API is running on http://localhost:5206'
        : 'Error calling API. Please check your connection and try again.';
      this.greetingResponse.set(errorMessage);
    } finally {
      this.isLoading.set(false);
    }
  }
  
  updateNameInput(event: Event) {
    const target = event.target as HTMLInputElement;
    this.nameInput.set(target.value);
  }
  
  private getApiBaseUrl(): string {
    // Check if we're running in development (localhost)
    if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
      return 'http://localhost:5206';
    }
    
    // For Azure Static Web Apps with containerized API
    if (window.location.hostname.includes('.azurestaticapps.net')) {
      // This will be the URL of our containerized API (e.g., Azure Container Apps)
      // We'll set this as an environment variable during build
      // For now, using a placeholder - we'll configure this in CI/CD
      return 'https://bookrecommender-api.azurecontainerapps.io'; // Placeholder URL
    }
    
    // For other production environments
    // You could also read this from a configuration file or environment variable
    return ''; // Default to relative URLs for same-domain deployments
  }
}
