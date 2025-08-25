import { Component, OnInit, OnDestroy } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { BookService } from '../../services/book.service';
import { Book, ReadingStatus } from '../../models/book.models';

@Component({
  selector: 'app-browse-books',
  standalone: true,
  imports: [CommonModule, FormsModule],
  templateUrl: './browse-books.component.html',
  styleUrls: ['./browse-books.component.css']
})
export class BrowseBooksComponent implements OnInit, OnDestroy {
  books: Book[] = [];
  filteredBooks: Book[] = [];
  isLoading = true;
  errorMessage = '';
  successMessage = '';
  
  // Search and filter properties
  searchTerm = '';
  selectedGenre = '';
  availableGenres: string[] = [];
  
  // Track which books are being added to library
  addingToLibrary = new Set<number>();
  
  // Track success/error messages per book
  bookMessages = new Map<number, { type: 'success' | 'error', message: string, timeout?: any }>();
  
  constructor(private bookService: BookService) {}

  ngOnInit(): void {
    this.loadBooks();
  }

  loadBooks(): void {
    this.isLoading = true;
    this.errorMessage = '';
    
    this.bookService.getAllBooks().subscribe({
      next: (books) => {
        this.books = books;
        this.filteredBooks = books;
        this.extractGenres();
        this.isLoading = false;
      },
      error: (error) => {
        this.errorMessage = 'Failed to load books. Please try again.';
        this.isLoading = false;
        console.error('Error loading books:', error);
      }
    });
  }

  private extractGenres(): void {
    const genreSet = new Set<string>();
    this.books.forEach(book => {
      if (book.genre) {
        genreSet.add(book.genre);
      }
    });
    this.availableGenres = Array.from(genreSet).sort();
  }

  filterBooks(): void {
    let filtered = this.books;

    // Apply search filter
    if (this.searchTerm.trim()) {
      const searchLower = this.searchTerm.toLowerCase().trim();
      filtered = filtered.filter(book => 
        book.title.toLowerCase().includes(searchLower) ||
        book.author.toLowerCase().includes(searchLower) ||
        (book.description && book.description.toLowerCase().includes(searchLower))
      );
    }

    // Apply genre filter
    if (this.selectedGenre) {
      filtered = filtered.filter(book => book.genre === this.selectedGenre);
    }

    this.filteredBooks = filtered;
  }

  onSearchChange(): void {
    this.filterBooks();
  }

  onGenreChange(): void {
    this.filterBooks();
  }

  clearFilters(): void {
    this.searchTerm = '';
    this.selectedGenre = '';
    this.filteredBooks = this.books;
  }

  async addToLibrary(book: Book, status: ReadingStatus = ReadingStatus.ToRead): Promise<void> {
    if (this.addingToLibrary.has(book.id)) {
      return; // Already adding this book
    }

    this.addingToLibrary.add(book.id);
    this.clearBookMessage(book.id);
    
    // Clear any global error messages
    this.errorMessage = '';
    this.successMessage = '';

    try {
      await this.bookService.addBookToLibrary({
        bookId: book.id,
        readingStatus: status
      }).toPromise();
      
      // Show success message
      const statusLabel = this.getReadingStatusLabel(status);
      this.showBookMessage(book.id, 'success', `Added to library as "${statusLabel}"`);
      
    } catch (error: any) {
      console.error('Error adding book to library:', error);
      
      let errorMsg = 'Failed to add book to library';
      
      if (error.status === 400) {
        if (error.error?.message) {
          errorMsg = error.error.message;
        }
      } else if (error.status === 401) {
        errorMsg = 'Please log in to add books to your library';
      } else if (error.status === 404) {
        errorMsg = 'Book not found';
      } else if (error.status === 0 || error.status >= 500) {
        errorMsg = 'Server error. Please try again later.';
      }
      
      this.showBookMessage(book.id, 'error', errorMsg);
    } finally {
      this.addingToLibrary.delete(book.id);
    }
  }

  isAddingToLibrary(bookId: number): boolean {
    return this.addingToLibrary.has(bookId);
  }

  getBookCover(book: Book): string {
    return book.coverImageUrl || '/assets/images/default-book-cover.png';
  }

  formatDate(dateString?: string): string {
    if (!dateString) return '';
    return new Date(dateString).toLocaleDateString();
  }

  // Helper methods for message handling
  showBookMessage(bookId: number, type: 'success' | 'error', message: string): void {
    // Clear any existing timeout
    this.clearBookMessage(bookId);
    
    // Set new message with auto-clear timeout
    const timeout = setTimeout(() => {
      this.clearBookMessage(bookId);
    }, type === 'success' ? 3000 : 5000); // Success messages disappear faster
    
    this.bookMessages.set(bookId, { type, message, timeout });
  }
  
  clearBookMessage(bookId: number): void {
    const existing = this.bookMessages.get(bookId);
    if (existing?.timeout) {
      clearTimeout(existing.timeout);
    }
    this.bookMessages.delete(bookId);
  }
  
  getBookMessage(bookId: number): { type: 'success' | 'error', message: string } | null {
    return this.bookMessages.get(bookId) || null;
  }
  
  getReadingStatusLabel(status: ReadingStatus): string {
    switch (status) {
      case ReadingStatus.ToRead:
        return 'Want to Read';
      case ReadingStatus.Reading:
        return 'Currently Reading';
      case ReadingStatus.Read:
        return 'Read';
      case ReadingStatus.DNF:
        return 'Did Not Finish';
      default:
        return 'Unknown';
    }
  }
  
  // Clear all messages when component is destroyed
  ngOnDestroy(): void {
    this.bookMessages.forEach((message) => {
      if (message.timeout) {
        clearTimeout(message.timeout);
      }
    });
    this.bookMessages.clear();
  }

  // Make ReadingStatus enum available to template
  ReadingStatus = ReadingStatus;
}
