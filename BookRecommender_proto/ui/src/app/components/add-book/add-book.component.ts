import { Component, OnInit } from '@angular/core';
import { FormBuilder, FormGroup, Validators, ReactiveFormsModule } from '@angular/forms';
import { Router } from '@angular/router';
import { CommonModule } from '@angular/common';
import { BookService } from '../../services/book.service';
import { CreateBookRequest } from '../../models/book.models';

@Component({
  selector: 'app-add-book',
  standalone: true,
  imports: [CommonModule, ReactiveFormsModule],
  templateUrl: './add-book.component.html',
  styleUrls: ['./add-book.component.css']
})
export class AddBookComponent implements OnInit {
  addBookForm: FormGroup;
  isLoading = false;
  errorMessage = '';
  successMessage = '';

  constructor(
    private fb: FormBuilder,
    private bookService: BookService,
    private router: Router
  ) {
    this.addBookForm = this.fb.group({
      title: ['', [Validators.required, Validators.maxLength(255)]],
      author: ['', [Validators.required, Validators.maxLength(255)]],
      isbn: ['', [Validators.maxLength(20)]],
      description: ['', [Validators.maxLength(2000)]],
      publicationDate: [''],
      genre: ['', [Validators.maxLength(100)]],
      pageCount: ['', [Validators.min(1)]],
      coverImageUrl: ['', [Validators.maxLength(500)]]
    });
  }

  ngOnInit(): void {}

  onSubmit(): void {
    if (this.addBookForm.valid) {
      this.isLoading = true;
      this.errorMessage = '';
      this.successMessage = '';

      const bookData: CreateBookRequest = {
        title: this.addBookForm.value.title.trim(),
        author: this.addBookForm.value.author.trim(),
        isbn: this.addBookForm.value.isbn?.trim() || undefined,
        description: this.addBookForm.value.description?.trim() || undefined,
        publicationDate: this.addBookForm.value.publicationDate || undefined,
        genre: this.addBookForm.value.genre?.trim() || undefined,
        pageCount: this.addBookForm.value.pageCount || undefined,
        coverImageUrl: this.addBookForm.value.coverImageUrl?.trim() || undefined
      };

      this.bookService.createBook(bookData).subscribe({
        next: (createdBook) => {
          this.isLoading = false;
          this.successMessage = `Book "${createdBook.title}" has been added successfully!`;
          
          // Reset form after success
          setTimeout(() => {
            this.addBookForm.reset();
            this.successMessage = '';
          }, 3000);
        },
        error: (error) => {
          this.isLoading = false;
          this.errorMessage = error.error?.message || 'Failed to add book. Please try again.';
        }
      });
    } else {
      // Mark all fields as touched to show validation errors
      Object.keys(this.addBookForm.controls).forEach(key => {
        this.addBookForm.get(key)?.markAsTouched();
      });
    }
  }

  onCancel(): void {
    this.router.navigate(['/dashboard']);
  }
}
