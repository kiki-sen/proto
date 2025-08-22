import { Component, signal, OnInit } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { HttpClient } from '@angular/common/http';
import { FormsModule } from '@angular/forms';
import { inject } from '@angular/core';
import { ConfigService } from './config.service';

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
}
