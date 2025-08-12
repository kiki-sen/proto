import { CommonModule } from '@angular/common';
import { Component, signal } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { FormsModule } from '@angular/forms';
import { HttpClient, HttpClientModule } from '@angular/common/http';
import { ConfigService } from './config.service';

interface User { id: number; name: string; }
interface Book { id: number; title: string; author: string; }
  interface RecVM {
  id: number;
  title: string;
  author: string;
  reason: string;
}

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, FormsModule, HttpClientModule, CommonModule],
  templateUrl: './app.html',
  styleUrls: ['./app.css']
})
export class App {
  protected readonly title = signal('book-recommender-ui');
  name = '';
  response = '';

  // Declare all bound properties
  newUserName = '';
  users: any[] = [];

  newBookTitle = '';
  newBookAuthor = '';
  books: any[] = [];

  selectedUserId: number | null = null;
  selectedBookId: number | null = null;
  readingHistory: Book[] = [];

  recommendations: RecVM[] = [];

  constructor(private http: HttpClient,
              private configService: ConfigService
  ) {}

  // POST a relation (user read book)
  markAsRead() {
    if (this.selectedUserId == null || this.selectedBookId == null) return;

    // Option A: generic join endpoint
    this.http.post(
      `${this.configService.apiUrl}/userbooks`,
      { userId: this.selectedUserId, bookId: this.selectedBookId }
    ).subscribe({
      next: () => this.loadReadingHistory(),
      error: err => console.error(err)
    });

    // Option B (if you implement it): `${api}/users/${id}/read?bookId=${bookId}`
  }

  // GET reading history for selected user
  loadReadingHistory() {
    if (this.selectedUserId == null) return;

    // Endpoint should return Book[]
    this.http.get<Book[]>(
      `${this.configService.apiUrl}/users/${this.selectedUserId}/books`
    ).subscribe({
      next: data => this.readingHistory = data,
      error: err => console.error(err)
    });
  }

  // Users
  createUser() {
    this.http.post(`${this.configService.apiUrl}/users`, { name: this.newUserName })
      .subscribe(() => {
        this.newUserName = '';
        this.loadUsers();
      });
  }

  loadUsers() {
    this.http.get<any[]>(`${this.configService.apiUrl}/users`)
      .subscribe(data => this.users = data);
  }

  // Books
  createBook() {
    this.http.post(`${this.configService.apiUrl}/books`, {
      title: this.newBookTitle,
      author: this.newBookAuthor
    }).subscribe(() => {
      this.newBookTitle = '';
      this.newBookAuthor = '';
      this.loadBooks();
    });
  }

  loadBooks() {
    this.http.get<any[]>(`${this.configService.apiUrl}/books`)
      .subscribe(data => this.books = data);
  }

  // Recommendations
  getRecommendations() {
    if (this.selectedUserId == null) return;

    this.http.get<RecVM[]>(
      `${this.configService.apiUrl}/recommendations/${this.selectedUserId}`
    ).subscribe({
      next: data => this.recommendations = data ?? [],
      error: err => {
        console.error(err);
        this.recommendations = [];
      }
    });
  }

  ngOnInit() {
    this.loadUsers();
    this.loadBooks();
  }
}
