
#ifndef DICE_ReportType_h
#define DICE_ReportType_h


@protocol ReportTypeMatchPredicate;
@class ImportProcess;
@class Report;



/**
 * This is a content enumeration visitor that aggregates information about the content entries
 * during the enumeration.  An instance of this class should be used as the first visitor of
 * each content entry then passed to the predicates so they can use the information as the
 * enumeration proceeds.
 */
@interface ContentEnumerationInfo : NSObject

/**
 * This will be nil until a base directory is found.  After a base directory is found, this
 * value may still change as the enumeration Once multiple unique root entries are
 * discovered, this value will become the empty string, @"".
 */
@property (readonly, nullable, nonatomic) NSString *baseDir;
/**
 * This is a convenience accessor that returns YES if baseDir is non-nil and non-zero length.
 */
@property (readonly, nonatomic) BOOL hasBaseDir;
@property (readonly, nonatomic) NSUInteger entryCount;
@property (readonly, nonatomic) uint64_t totalContentSize;

- (void)addInfoForEntryPath:(nonnull NSString *)path size:(uint64_t)contentSize;

@end


@protocol ReportType <NSObject>

- (nonnull NSString *)reportTypeId;

// TODO: pre-load path attributes and pass to method; use NSURL:resourceValuesForKeys:error:
- (BOOL)couldImportFromPath:(nonnull NSURL *)path;
/**
 * Create a predicate to evaluate the enumerated contents of a report archive.
 * The predicate need not be thread-safe, and will be thrown away after the enumeration
 * is complete.  Therefore, the ReportType should not attempt to preserve or recycle
 * the created predicate.
 *
 * @return (id<ReportTypeMatchPredicate>) an object conforming to the ReportTypeMatchPredicate protocol
 *
 * @todo maybe add the archive url or base directory?  we'll see later
 */
- (nonnull id<ReportTypeMatchPredicate>)createContentMatchingPredicate;

/**
 * Create the ImportProcess with the steps to import the content of the given report from
 * its base directory.  Implement this method in a thread-safe manner.  This method will 
 * run on a background thread in case file operations are necessary to create the ImportProcess.
 *
 * @param report
 * @return nil if this type cannot import the content of the given report
 */
// TODO: remove toDir and import to Report.importDir
- (nullable ImportProcess *)createProcessToImportReport:(nonnull Report *)report;

@end


/**
 * This protocol allows the inspection of a collection of report content entries on
 * behalf of its associated ReportType to determine whether the content could potentially
 * match the ReportType.  The purpose of this protocol is to minimize the number of times
 * the entries of a report archive are enumerated, especially in the common case that
 * the archive contains an XYZ raster tile set.  With this protocol, an agent can request
 * an instance of this protocol from each known ReportType, then enumerate the contents of
 * an archive just once, passing the entries to the ReportTypeMatchPredicate of each
 * ReportType.  The predicates aggregate the necessary information during the enumeration
 * and determine their results with respect to the content entries they inspected.  The
 * enumerating agent can then retrieve the result from each predicate.
 */
@protocol ReportTypeMatchPredicate <NSObject>

/**
 * Return the ReportType that created this predicate.
 *
 * @return (id<ReportType>)
 */
@property (readonly, nonnull) id<ReportType> reportType;

/**
 * (BOOL) whether the content entries provided to this predicate could match its creating ReportType
 */
@property (readonly) BOOL contentCouldMatch;

/**
 * Consider the given content entry with respect to this predicate's match criteria.
 *
 * @param name (NSString *) the name, usually including a file path, of a content file entry
 * @param uti (CFStringRef) the most probable uniform type identifier fo the content entry
 */
- (void)considerContentEntryWithName:(nonnull NSString *)name probableUti:(nullable CFStringRef)uti contentInfo:(nonnull ContentEnumerationInfo *)info;

@end


#endif
