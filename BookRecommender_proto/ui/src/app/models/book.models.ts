export enum ReadingStatus {
  ToRead = 0,
  Reading = 1,
  Read = 2,
  DNF = 3 // Did Not Finish
}

export interface Book {
  id: number;
  title: string;
  author: string;
  isbn?: string;
  description?: string;
  publicationDate?: string;
  genre?: string;
  pageCount?: number;
  coverImageUrl?: string;
  createdAt: string;
  createdByUserId: number;
  createdByUserEmail: string;
}

export interface CreateBookRequest {
  title: string;
  author: string;
  isbn?: string;
  description?: string;
  publicationDate?: string;
  genre?: string;
  pageCount?: number;
  coverImageUrl?: string;
}

export interface UserBook {
  id: number;
  userId: number;
  book: Book;
  readingStatus: ReadingStatus;
  rating?: number;
  review?: string;
  dateStarted?: string;
  dateFinished?: string;
  addedAt: string;
  updatedAt: string;
}

export interface AddBookToUserRequest {
  bookId: number;
  readingStatus?: ReadingStatus;
}

export interface UpdateUserBookRequest {
  readingStatus?: ReadingStatus;
  rating?: number;
  review?: string;
  dateStarted?: string | null;
  dateFinished?: string | null;
}

export const ReadingStatusLabels = {
  [ReadingStatus.ToRead]: 'To Read',
  [ReadingStatus.Reading]: 'Currently Reading',
  [ReadingStatus.Read]: 'Read',
  [ReadingStatus.DNF]: 'Did Not Finish'
};

export const ReadingStatusColors = {
  [ReadingStatus.ToRead]: '#6c757d',
  [ReadingStatus.Reading]: '#007bff',
  [ReadingStatus.Read]: '#28a745',
  [ReadingStatus.DNF]: '#dc3545'
};
