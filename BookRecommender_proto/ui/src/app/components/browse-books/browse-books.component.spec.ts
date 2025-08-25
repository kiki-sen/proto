import { ComponentFixture, TestBed } from '@angular/core/testing';
import { provideHttpClient } from '@angular/common/http';
import { provideHttpClientTesting } from '@angular/common/http/testing';
import { BrowseBooksComponent } from './browse-books.component';
import { BookService } from '../../services/book.service';
import { AuthService } from '../../services/auth.service';
import { BehaviorSubject, of } from 'rxjs';
import { AuthState } from '../../models/auth.models';

// Mock services
class MockBookService {
  getAllBooks() {
    return of([
      {
        id: 1,
        title: 'Test Book',
        author: 'Test Author',
        genre: 'Fiction',
        pageCount: 200,
        createdAt: new Date().toISOString(),
        createdByUserId: 1,
        createdByUserEmail: 'test@example.com'
      }
    ]);
  }

  addBookToLibrary() {
    return of({ message: 'Book added successfully' });
  }
}

class MockAuthService {
  private authState = new BehaviorSubject<AuthState>({
    isLoggedIn: false,
    user: null,
    token: null
  });
  
  public authState$ = this.authState.asObservable();
  
  getToken() {
    return 'mock-token';
  }
  
  logout() {
    // Mock logout method
  }
}

describe('BrowseBooksComponent', () => {
  let component: BrowseBooksComponent;
  let fixture: ComponentFixture<BrowseBooksComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [BrowseBooksComponent],
      providers: [
        provideHttpClient(),
        provideHttpClientTesting(),
        { provide: BookService, useClass: MockBookService },
        { provide: AuthService, useClass: MockAuthService }
      ]
    }).compileComponents();

    fixture = TestBed.createComponent(BrowseBooksComponent);
    component = fixture.componentInstance;
  });

  it('should create', () => {
    expect(component).toBeTruthy();
  });

  it('should initialize with loading state', () => {
    expect(component.isLoading).toBe(true);
    expect(component.books).toEqual([]);
    expect(component.filteredBooks).toEqual([]);
  });

  it('should load books on init', async () => {
    await fixture.whenStable();
    fixture.detectChanges();
    
    expect(component.books.length).toBe(1);
    expect(component.books[0].title).toBe('Test Book');
    expect(component.isLoading).toBe(false);
  });

  it('should filter books by search term', async () => {
    await fixture.whenStable();
    fixture.detectChanges();
    
    // Search for existing book
    component.searchTerm = 'Test';
    component.onSearchChange();
    expect(component.filteredBooks.length).toBe(1);
    
    // Search for non-existing book
    component.searchTerm = 'NonExistent';
    component.onSearchChange();
    expect(component.filteredBooks.length).toBe(0);
  });

  it('should clear filters', async () => {
    await fixture.whenStable();
    fixture.detectChanges();
    
    component.searchTerm = 'test';
    component.selectedGenre = 'Fiction';
    component.clearFilters();
    
    expect(component.searchTerm).toBe('');
    expect(component.selectedGenre).toBe('');
    expect(component.filteredBooks).toEqual(component.books);
  });

  it('should show reading status labels correctly', () => {
    expect(component.getReadingStatusLabel(0)).toBe('Want to Read'); // ToRead
    expect(component.getReadingStatusLabel(1)).toBe('Currently Reading'); // Reading
    expect(component.getReadingStatusLabel(2)).toBe('Read'); // Read
    expect(component.getReadingStatusLabel(3)).toBe('Did Not Finish'); // DNF
  });
});
