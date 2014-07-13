#import "NYPLAsync.h"
#import "NYPLBook.h"
#import "NYPLOPDSEntry.h"
#import "NYPLOPDSFeed.h"
#import "NYPLOPDSLink.h"
#import "NYPLOPDSRelation.h"
#import "NYPLMyBooksRegistry.h"

#import "NYPLCatalogCategory.h"

@interface NYPLCatalogCategory ()

@property (nonatomic) BOOL currentlyFetchingNextURL;
@property (nonatomic) NSArray *books;
@property (nonatomic) NSUInteger greatestPreparationIndex;
@property (nonatomic) NSURL *nextURL;
@property (nonatomic) NSString *title;

@end

// If fewer than this many books are currently available when |prepareForBookIndex:| is called, an
// attempt to fetch more books will be made.
static NSUInteger const preloadThreshold = 100;

@implementation NYPLCatalogCategory

+ (void)withURL:(NSURL *)URL handler:(void (^)(NYPLCatalogCategory *category))handler
{
  [NYPLOPDSFeed
   withURL:URL
   completionHandler:^(NYPLOPDSFeed *const acquisitionFeed) {
     if(!acquisitionFeed) {
       NYPLLOG(@"Failed to retrieve acquisition feed.");
       NYPLAsyncDispatch(^{handler(nil);});
       return;
     }
     
     NSMutableArray *const books = [NSMutableArray arrayWithCapacity:acquisitionFeed.entries.count];
     
     for(NYPLOPDSEntry *const entry in acquisitionFeed.entries) {
       NYPLBook *const book = [NYPLBook bookWithEntry:entry];
       if(!book) {
         NYPLLOG(@"Failed to create book from entry.");
         continue;
       }
       [books addObject:book];
     }
     
     NSURL *nextURL = nil;
     
     for(NYPLOPDSLink *const link in acquisitionFeed.links) {
       if([link.rel isEqualToString:NYPLOPDSRelationPaginationNext]) {
         nextURL = link.href;
         break;
       }
     }
     
     NYPLCatalogCategory *const category = [[NYPLCatalogCategory alloc]
                                            initWithBooks:books
                                            nextURL:nextURL
                                            title:acquisitionFeed.title];
     
     NYPLAsyncDispatch(^{handler(category);});
   }];
}

- (instancetype)initWithBooks:(NSArray *const)books
                      nextURL:(NSURL *const)nextURL
                        title:(NSString *const)title
{
  self = [super init];
  if(!self) return nil;
  
  if(!(books && title)) {
    @throw NSInvalidArgumentException;
  }
  
  self.books = books;
  self.nextURL = nextURL;
  self.title = title;
  
  [[NSNotificationCenter defaultCenter]
   addObserverForName:NYPLBookRegistryDidChange
   object:nil
   queue:[NSOperationQueue mainQueue]
   usingBlock:^(__attribute__((unused)) NSNotification *note) {
     [self refreshBooks];
   }];

  return self;
}

- (void)prepareForBookIndex:(NSUInteger)bookIndex
{
  if(bookIndex >= self.books.count) {
    @throw NSInvalidArgumentException;
  }
  
  if(bookIndex < self.greatestPreparationIndex) {
    return;
  }
  
  self.greatestPreparationIndex = bookIndex;
  
  if(self.currentlyFetchingNextURL) return;
  
  if(!self.nextURL) return;
  
  if(self.books.count - bookIndex > preloadThreshold) {
    return;
  }
  
  self.currentlyFetchingNextURL = YES;
  
  [NYPLCatalogCategory
   withURL:self.nextURL
   handler:^(NYPLCatalogCategory *const category) {
     [[NSOperationQueue mainQueue] addOperationWithBlock:^{
       if(!category) {
         NYPLLOG(@"Failed to fetch next page.");
         self.currentlyFetchingNextURL = NO;
         return;
       }
       
       NSMutableArray *const books = [self.books mutableCopy];
       [books addObjectsFromArray:category.books];
       self.books = books;
       self.nextURL = category.nextURL;
       self.currentlyFetchingNextURL = NO;
       
       [self prepareForBookIndex:self.greatestPreparationIndex];
       
       [self.delegate catalogCategory:self didUpdateBooks:self.books];
     }];
   }];
}

- (void)refreshBooks
{
  NSMutableArray *const refreshedBooks = [NSMutableArray arrayWithCapacity:self.books.count];
  
  for(NYPLBook *const book in self.books) {
    NYPLBook *const refreshedBook = [[NYPLMyBooksRegistry sharedRegistry]
                                     bookForIdentifier:book.identifier];
    if(refreshedBook) {
      [refreshedBooks addObject:refreshedBook];
    } else {
      [refreshedBooks addObject:book];
    }
  }
  
  self.books = refreshedBooks;
  
  [self.delegate catalogCategory:self didUpdateBooks:self.books];
}

#pragma mark NSObject

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
