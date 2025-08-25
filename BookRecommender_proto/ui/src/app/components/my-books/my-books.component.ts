import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { BookService } from '../../services/book.service';
import { UserBook, ReadingStatus, ReadingStatusLabels, ReadingStatusColors } from '../../models/book.models';

@Component({
  selector: 'app-my-books',
  standalone: true,
  imports: [CommonModule, RouterLink],
  templateUrl: './my-books.component.html',
  styleUrls: ['./my-books.component.css']
})
export class MyBooksComponent implements OnInit {
  userBooks: UserBook[] = [];
  filteredBooks: UserBook[] = [];
  isLoading = true;
  errorMessage = '';
  
  // Filter properties
  selectedStatus: ReadingStatus | 'all' = 'all';
  
  // Expose enums and labels to template
  ReadingStatus = ReadingStatus;
  ReadingStatusLabels = ReadingStatusLabels;
  ReadingStatusColors = ReadingStatusColors;

  constructor(private bookService: BookService) {}

  ngOnInit(): void {
    this.loadUserBooks();
  }

  loadUserBooks(): void {
    this.isLoading = true;
    this.errorMessage = '';
    
    this.bookService.getUserBooks().subscribe({
      next: (books) => {
        this.userBooks = books;
        this.filteredBooks = books;
        this.isLoading = false;
      },
      error: (error) => {
        this.errorMessage = 'Failed to load your books. Please try again.';
        this.isLoading = false;
        console.error('Error loading user books:', error);
      }
    });
  }

  filterBooks(): void {
    if (this.selectedStatus === 'all') {
      this.filteredBooks = this.userBooks;
    } else {
      this.filteredBooks = this.userBooks.filter(ub => ub.readingStatus === this.selectedStatus);
    }
  }

  onFilterChange(status: ReadingStatus | 'all'): void {
    this.selectedStatus = status;
    this.filterBooks();
  }

  toggleReadingStatus(userBook: UserBook): void {
    const newStatus = userBook.readingStatus === ReadingStatus.Read 
      ? ReadingStatus.ToRead 
      : ReadingStatus.Read;

    const updateRequest = {
      readingStatus: newStatus,
      dateFinished: newStatus === ReadingStatus.Read ? new Date().toISOString() : null
    };

    this.bookService.updateUserBook(userBook.id, updateRequest).subscribe({
      next: (updatedUserBook) => {
        // Update the book in our arrays
        const index = this.userBooks.findIndex(ub => ub.id === userBook.id);
        if (index !== -1) {
          this.userBooks[index] = updatedUserBook;
        }
        this.filterBooks(); // Re-apply filter
      },
      error: (error) => {
        console.error('Error updating book status:', error);
        // You could show an error message here
      }
    });
  }

  updateReadingStatus(userBook: UserBook, newStatus: ReadingStatus): void {
    const updateRequest = {
      readingStatus: newStatus,
      dateStarted: newStatus === ReadingStatus.Reading ? new Date().toISOString() : userBook.dateStarted,
      dateFinished: newStatus === ReadingStatus.Read ? new Date().toISOString() : null
    };

    this.bookService.updateUserBook(userBook.id, updateRequest).subscribe({
      next: (updatedUserBook) => {
        // Update the book in our arrays
        const index = this.userBooks.findIndex(ub => ub.id === userBook.id);
        if (index !== -1) {
          this.userBooks[index] = updatedUserBook;
        }
        this.filterBooks(); // Re-apply filter
      },
      error: (error) => {
        console.error('Error updating book status:', error);
      }
    });
  }

  removeBook(userBook: UserBook): void {
    if (confirm(`Are you sure you want to remove "${userBook.book.title}" from your library?`)) {
      this.bookService.removeBookFromLibrary(userBook.id).subscribe({
        next: () => {
          this.userBooks = this.userBooks.filter(ub => ub.id !== userBook.id);
          this.filterBooks();
        },
        error: (error) => {
          console.error('Error removing book:', error);
        }
      });
    }
  }

  getStatusColor(status: ReadingStatus): string {
    return ReadingStatusColors[status];
  }

  getStatusLabel(status: ReadingStatus): string {
    return ReadingStatusLabels[status];
  }

  formatDate(dateString?: string): string {
    if (!dateString) return '';
    return new Date(dateString).toLocaleDateString();
  }

  getCountByStatus(status: ReadingStatus): number {
    return this.userBooks.filter(ub => ub.readingStatus === status).length;
  }

  onStatusChange(userBook: UserBook, event: Event): void {
    const select = event.target as HTMLSelectElement;
    const newStatus = parseInt(select.value) as ReadingStatus;
    this.updateReadingStatus(userBook, newStatus);
  }
}
