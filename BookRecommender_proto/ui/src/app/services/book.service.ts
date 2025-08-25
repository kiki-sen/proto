import { Injectable } from '@angular/core';
import { HttpClient, HttpHeaders } from '@angular/common/http';
import { Observable, catchError, throwError } from 'rxjs';
import { AuthService } from './auth.service';
import { ConfigService } from '../config.service';
import { 
  Book, 
  CreateBookRequest, 
  UserBook, 
  AddBookToUserRequest, 
  UpdateUserBookRequest 
} from '../models/book.models';

@Injectable({
  providedIn: 'root'
})
export class BookService {
  private get API_URL(): string {
    return `${this.configService.getApiUrl()}/api`;
  }

  constructor(
    private http: HttpClient,
    private authService: AuthService,
    private configService: ConfigService
  ) {}

  private getAuthHeaders(): HttpHeaders {
    const token = this.authService.getToken();
    return new HttpHeaders().set('Authorization', `Bearer ${token}`);
  }

  // Book management
  getAllBooks(): Observable<Book[]> {
    return this.http.get<Book[]>(`${this.API_URL}/books`)
      .pipe(
        catchError(error => {
          console.error('Error fetching books:', error);
          return throwError(() => error);
        })
      );
  }

  getBookById(id: number): Observable<Book> {
    return this.http.get<Book>(`${this.API_URL}/books/${id}`)
      .pipe(
        catchError(error => {
          console.error('Error fetching book:', error);
          return throwError(() => error);
        })
      );
  }

  createBook(bookData: CreateBookRequest): Observable<Book> {
    const headers = this.getAuthHeaders();
    return this.http.post<Book>(`${this.API_URL}/books`, bookData, { headers })
      .pipe(
        catchError(error => {
          console.error('Error creating book:', error);
          return throwError(() => error);
        })
      );
  }

  // User's book library management
  getUserBooks(): Observable<UserBook[]> {
    const headers = this.getAuthHeaders();
    return this.http.get<UserBook[]>(`${this.API_URL}/my-books`, { headers })
      .pipe(
        catchError(error => {
          console.error('Error fetching user books:', error);
          return throwError(() => error);
        })
      );
  }

  addBookToLibrary(request: AddBookToUserRequest): Observable<any> {
    const headers = this.getAuthHeaders();
    return this.http.post(`${this.API_URL}/my-books`, request, { headers })
      .pipe(
        catchError(error => {
          console.error('Error adding book to library:', error);
          return throwError(() => error);
        })
      );
  }

  updateUserBook(userBookId: number, request: UpdateUserBookRequest): Observable<UserBook> {
    const headers = this.getAuthHeaders();
    return this.http.put<UserBook>(`${this.API_URL}/my-books/${userBookId}`, request, { headers })
      .pipe(
        catchError(error => {
          console.error('Error updating user book:', error);
          return throwError(() => error);
        })
      );
  }

  removeBookFromLibrary(userBookId: number): Observable<any> {
    const headers = this.getAuthHeaders();
    return this.http.delete(`${this.API_URL}/my-books/${userBookId}`, { headers })
      .pipe(
        catchError(error => {
          console.error('Error removing book from library:', error);
          return throwError(() => error);
        })
      );
  }

  // Helper method to mark book as read/unread
  markAsRead(userBookId: number, isRead: boolean): Observable<UserBook> {
    const request: UpdateUserBookRequest = {
      readingStatus: isRead ? 2 : 0, // Read : ToRead
      dateFinished: isRead ? new Date().toISOString() : null
    };
    
    return this.updateUserBook(userBookId, request);
  }
}
